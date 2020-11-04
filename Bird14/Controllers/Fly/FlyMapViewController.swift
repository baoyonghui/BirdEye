//
//  MapViewController.swift
//  Zond
//
//  Created by Evgeny Agamirzov on 4/24/19.
//  Copyright © 2019 Evgeny Agamirzov. All rights reserved.
//

import os.log

import CoreLocation
import DJISDK
import MapKit
import MapKitGoogleStyler
import UIKit

class FlyMapViewController : UIViewController {
    // Stored properties
    private var mapView = MapView()
    private var tapRecognizer = UILongPressGestureRecognizer()
    private var panRecognizer = UIPanGestureRecognizer()
    private var aircraft = MovingObject(CLLocationCoordinate2D(), 0.0, .aircraft)
    private var home = MovingObject(CLLocationCoordinate2D(), 0.0, .home)
    private(set) var missionPolygon: MissionPolygon?

    // Notifyer properties
    var logConsole: ((_ message: String, _ type: OSLogType) -> Void)?

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    init() {
        super.init(nibName: nil, bundle: nil)
        setUp()
    }

    func setUp(){
        mapView.delegate = self
        view = mapView

        tapRecognizer.delegate = self
        tapRecognizer.minimumPressDuration = 1
        tapRecognizer.addTarget(self, action: #selector(handleTap(sender:)))

        panRecognizer.delegate = self
        panRecognizer.minimumNumberOfTouches = 1
        panRecognizer.maximumNumberOfTouches = 1
        panRecognizer.addTarget(self, action: #selector(handlePolygonDrag(sender:)))

        registerListeners()
        configureTileOverlay()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        repositionLegalLabels()
    }
    
    private func configureTileOverlay() {
        // We first need to have the path of the overlay configuration JSON
        guard let overlayFileURLString = Bundle.main.path(forResource: "MapStyle", ofType: "json") else {
                return
        }
        let overlayFileURL = URL(fileURLWithPath: overlayFileURLString)
        print (overlayFileURL)
        
        // After that, you can create the tile overlay using MapKitGoogleStyler
        guard let tileOverlay = try? MapKitGoogleStyler.buildOverlay(with: overlayFileURL) else {
            return
        }
        
        // And finally add it to your MKMapView
        mapView.addOverlay(tileOverlay)
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        //mapView.delegate = self
        setUp()
        configureTileOverlay()
    }
}

// Public methods
extension FlyMapViewController {

    func trackAircraft(_ enable: Bool) -> Bool {
        if trackObject(aircraft, enable) {
            return true
        } else {
            logConsole?("Unable to track aircraft. Aircraft location unknown.", .error)
            return false
        }
    }

    func showMissionPolygon(_ rawCoordinates: [[Double]]) {
        if let polygon = missionPolygon {
            print ("do it")
            var coordinates: [CLLocationCoordinate2D] = []
            for coordinate in rawCoordinates {
                let lat = coordinate[1]
                let lon = coordinate[0]
                coordinates.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
            }
            polygon.replaceAllVertices(with: coordinates)
            if let center = polygon.center {
                focusOnCoordinate(center)
            }
        }else{
            print ("not do it")
            missionPolygon?.missionState = MissionState.editing
            var polygonCoordinates:[CLLocationCoordinate2D] = []
            
            for latlng in rawCoordinates{
                polygonCoordinates.append(CLLocationCoordinate2D(latitude: latlng[1], longitude:latlng[0]))
            }

            missionPolygon = MissionPolygon(polygonCoordinates)
            missionPolygon!.updated = {
                if let renderer = self.mapView.renderer(for: self.missionPolygon!) as? MissionRenderer {
                    renderer.redrawRenderer()
                }
            }
            mapView.addOverlay(missionPolygon!)
        }
    }

    func missionCoordinates() -> [CLLocationCoordinate2D] {
        if let renderer = self.mapView.renderer(for: self.missionPolygon!) as? MissionRenderer {
            return renderer.missionCoordinates()
        } else {
            return []
        }
    }

    func repositionLegalLabels() {
        mapView.repositionLegalLabels()
    }
}

// Private methods
extension FlyMapViewController {
    private func registerListeners() {
        Environment.locationService.aircraftLocationListeners.append({ location in
            self.showObject(self.aircraft, location)
            self.missionPolygon?.aircraftLocation = location
        })
        Environment.locationService.aircraftHeadingChanged = { heading in
            if (heading != nil) {
                self.aircraft.heading = heading!
            }
        }
        Environment.locationService.homeLocationChanged = { location in
            self.showObject(self.home, location)
        }
        Environment.missionViewController.stateListeners.append({ state in
            self.missionPolygon?.missionState = state
            self.enableMissionPolygonInteration(false)
        })
    }

    private func enableMissionPolygonInteration(_ enable: Bool) {
        if enable {
            mapView.addGestureRecognizer(tapRecognizer)
            mapView.addGestureRecognizer(panRecognizer)
        } else {
            mapView.removeGestureRecognizer(tapRecognizer)
            mapView.removeGestureRecognizer(panRecognizer)
        }
    }

    private func enableMapInteraction(_ enable: Bool) {
        mapView.isScrollEnabled = enable
        mapView.isZoomEnabled = enable
        mapView.isUserInteractionEnabled = enable
    }

    private func objectPresentOnMap(_ object: MovingObject) -> Bool {
        return mapView.annotations.contains(where: { annotation in
            return annotation as? MovingObject == object
        })
    }

    private func showObject(_ object: MovingObject, _ location: CLLocation?) {
        if location != nil {
            object.coordinate = location!.coordinate
            if !objectPresentOnMap(object) {
                mapView.addAnnotation(object)
            }
        } else if objectPresentOnMap(object) {
            mapView.removeAnnotation(object)
        }
    }

    private func trackObject(_ object: MovingObject, _ enable: Bool) -> Bool {
        if objectPresentOnMap(object) {
            object.isTracked = enable
            if enable {
                focusOnCoordinate(object.coordinate)
                object.coordinateChanged = { coordinate in
                    self.focusOnCoordinate(coordinate)
                }
            } else {
                object.coordinateChanged = nil
            }
            return true
        } else {
            return false
        }
    }

    func focusOnCoordinate(_ coordinate: CLLocationCoordinate2D) {
        let region = MKCoordinateRegion(center: coordinate,
                                        latitudinalMeters: CLLocationDistance(exactly: 400)!,
                                        longitudinalMeters: CLLocationDistance(exactly: 400)!)
        mapView.setRegion(mapView.regionThatFits(region), animated: true)
    }

    private func movingObjectView(for movingObject: MovingObject, on mapView: MKMapView) -> MovingObjectView? {
        //let movingObjectView = mapView.dequeueReusableAnnotationView(withIdentifier: NSStringFromClass(MovingObject.self), for: movingObject) as? MovingObjectView
        let movingObjectView = mapView.dequeueReusableAnnotationView(withIdentifier: NSStringFromClass(MovingObject.self)) as? MovingObjectView
        
        if movingObjectView != nil {
            switch movingObject.type {
                case .user:
                    movingObject.headingChanged = { heading in
                        movingObjectView!.onHeadingChanged(heading)
                    }
                    let image = #imageLiteral(resourceName: "userPin")
                    movingObjectView!.image = image.color(Colors.Overlay.userLocationColor)
                case .aircraft:
                    movingObject.headingChanged = { heading in
                        movingObjectView!.onHeadingChanged(heading)
                    }
                    let image = #imageLiteral(resourceName: "aircraftPin")
                    movingObjectView!.image = image.color(Colors.Overlay.aircraftLocationColor)
                case .home:
                    movingObjectView!.image = #imageLiteral(resourceName: "homePin")
            }
        }
        return movingObjectView
    }
}

// Display annotations and renderers
extension FlyMapViewController : MKMapViewDelegate {
    internal func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        var annotationView: MKAnnotationView?
        if let annotation = annotation as? MovingObject {
            annotationView = movingObjectView(for: annotation, on: mapView)
        }
        return annotationView
    }

    internal func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
        for view in views {
            if let movingObjectView = view as? MovingObjectView {
                movingObjectView.addedToMapView()
            }
        }
    }

    internal func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, didChange newState: MKAnnotationView.DragState, fromOldState oldState: MKAnnotationView.DragState) {
        switch newState {
            case .starting:
                view.dragState = .dragging
            case .ending, .canceling:
                view.dragState = .none
            default:
                break
        }
    }

    internal func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        
        // This is the final step. This code can be copied and pasted into your project
        // without thinking on it so much. It simply instantiates a MKTileOverlayRenderer
        // for displaying the tile overlay.
        if let tileOverlay = overlay as? MKTileOverlay {
            return MKTileOverlayRenderer(tileOverlay: tileOverlay)
        } else {
            //return MKOverlayRenderer(overlay: overlay)
            return MissionRenderer(overlay: overlay)
        }
    }

    func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
        repositionLegalLabels()
    }

    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
       repositionLegalLabels()
    }
}

// Handle custom gestures
extension FlyMapViewController : UIGestureRecognizerDelegate {
    internal func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    @objc private func handleTap(sender: UIGestureRecognizer) {
        if sender.state == .began && self.missionPolygon != nil {
            let touchCoordinate = mapView.convert(sender.location(in: mapView), toCoordinateFrom: mapView)
            if self.missionPolygon!.vertexContains(coordinate: touchCoordinate) {
                self.missionPolygon!.removeVetrex(at: missionPolygon!.dragIndex!)
            } else {
                self.missionPolygon!.appendVetrex(with: touchCoordinate)
            }
        }
    }

    @objc private func handlePolygonDrag(sender: UIGestureRecognizer) {
        let touchCoordinate = mapView.convert(sender.location(in: mapView), toCoordinateFrom: mapView)
        if let polygon = self.missionPolygon {
            let canDragPolygon = polygon.bodyContains(coordinate: touchCoordinate)
            let canDragVertex = polygon.vertexContains(coordinate: touchCoordinate)

            if !canDragVertex && !canDragPolygon {
                enableMapInteraction(true)
            } else if sender.state == .began {
                enableMapInteraction(false)
                polygon.computeOffsets(relativeTo: touchCoordinate)
            } else if sender.state == .changed && canDragVertex {
                polygon.moveVertex(following: touchCoordinate)
            } else if sender.state == .changed && canDragPolygon {
                polygon.movePolygon(following: touchCoordinate)
            } else if sender.state == .ended {
                enableMapInteraction(true)
            }
        } else {
            enableMapInteraction(true)
        }
    }
}
