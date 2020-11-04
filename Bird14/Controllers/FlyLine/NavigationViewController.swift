//
//  ControlViewController.swift
//  Zond
//
//  Created by Evgeny Agamirzov on 14.04.20.
//  Copyright © 2020 Evgeny Agamirzov. All rights reserved.
//

import UIKit
import SwiftHTTP
import DJISDK

class NavigationViewController : UIViewController {
    private var navigationView: NavigationView!

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    init() {
        super.init(nibName: nil, bundle: nil)
    }
    
    func setUp(){
        navigationView = NavigationView()
        registerListeners()
        view = navigationView
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setUp()
    }
}

// Private methods
extension NavigationViewController {
    func registerListeners() {
        navigationView.buttonSelected = { id, isSelected in
            switch id {
                case .simulator:
                    if isSelected {
                        let userLocation = Environment.mapViewController.userLocation
                        Environment.simulatorService.startSimulator(userLocation, { success in
                            if !success {
                                self.navigationView.deselectButton(with: .simulator)
                            }
                        })
                    } else {
                        Environment.simulatorService.stopSimulator({ _ in
                            self.navigationView.deselectButton(with: .simulator)
                        })
                    }
                case .user:
                    if Environment.mapViewController.trackUser(isSelected) {
                        self.navigationView.deselectButton(with: .aircraft)
                    } else {
                        self.navigationView.deselectButton(with: .user)
                    }
                case .aircraft:
                    if Environment.mapViewController.trackAircraft(isSelected) {
                        self.navigationView.deselectButton(with: .user)
                    } else {
                        self.navigationView.deselectButton(with: .aircraft)
                    }
            case .create:
                print ("create")
                Environment.mapViewController.createMissionPolygon()
            case .clear:
                Environment.mapViewController.createMissionPolygon()
            case .login:
                self.loginDJI(completionHandler: { (success:Bool) in
                    if success {
                        print("Successed to login to account")
                    } else {
                        print("Failed to login to account")
                    }
                })
            case .submit:
                self.submitFlyLine(completionHandler: { (success:Bool) in
                    if success {
                        print("Successed to submitFlyLine")
                    } else {
                        print("Failed to submitFlyLine")
                    }
                })
            }
        }
        Environment.connectionService.listeners.append({ model in
            if model == nil {
                self.navigationView.deselectButton(with: .simulator)
            }
        })
        Environment.locationService.aircraftLocationListeners.append({ location in
            if location == nil {
                self.navigationView.deselectButton(with: .aircraft)
            }
        })
    }
    
    private func loginDJI(completionHandler: @escaping (Bool) -> ()) {
        DJISDKManager.userAccountManager().logIntoDJIUserAccount(withAuthorizationRequired: false, withCompletion: { (state:DJIUserAccountState?, error:Error?)in
            if error != nil{
                print("\(String(describing: error))")
                completionHandler(false)
            }
            completionHandler(true)
        })
    }
    
    private func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
    
    private func submitFlyLine(completionHandler: @escaping (Bool) -> ()) {
        Environment.mapViewController.screenCapture(completionHandler: { (image:UIImage?) in
            if image != nil {
                print("Successed to screenCapture")
                if let data = image?.pngData() {
                    let filename = self.getDocumentsDirectory().appendingPathComponent("copy.png")
                    print ("filename \(filename)")
                    try? data.write(to: filename)
                    
                    let center:CLLocationCoordinate2D = Environment.mapViewController.missionPolygon?.center ?? CLLocationCoordinate2D(latitude: 33, longitude: 110)
                    let urlGetAddress:String = "https://api.map.baidu.com/geocoder?location=\(center.latitude),\(center.longitude)" +
                    "&output=json&key=E4805d16520de693a3fe707cdc962045"
                    HTTP.GET(urlGetAddress) { response in
                        if let err = response.error{
                            print ("error: \(err.localizedDescription)")
                            self.submitFlyLine2Svr(filename.absoluteString, address: "none",
                                                   province: "none", city: "none",
                                                   district: "none", cityCode: "none",
                                                   completionHandler: { (success:Bool) in
                                if success {
                                    print("Successed to submitFlyLine2Svr")
                                    completionHandler(true)
                                } else {
                                    print("Failed to submitFlyLine2Svr")
                                    completionHandler(false)
                                }
                            })
                            return
                        }
                        /*
                         {
                           "status": "OK",
                           "result": {
                             "location": {
                               "lng": 113,
                               "lat": 23
                             },
                             "formatted_address": "广东省佛山市禅城区尚塘大街",
                             "business": "",
                             "addressComponent": {
                               "city": "佛山市",
                               "direction": "",
                               "distance": "",
                               "district": "禅城区",
                               "province": "广东省",
                               "street": "尚塘大街",
                               "street_number": ""
                             },
                             "cityCode": 138
                           }
                         }
                         */

                        let respData:Data! = response.data
                        if let json = try? JSONSerialization.jsonObject(with: respData!, options: []) as? [String: Any]{
                            let address:Address? = Address(json:json)
                            self.submitFlyLine2Svr(filename.absoluteString, address: address?.result?.formatted_address ?? "none",
                                                   province: address?.result?.addressComponent?.province ?? "none",
                                                   city: address?.result?.addressComponent?.city ?? "none",
                                                   district: address?.result?.addressComponent?.district ?? "none",
                                                   cityCode: String(format: "%d", address?.result?.cityCode ?? 0),
                                                   completionHandler: { (success:Bool) in
                                if success {
                                    print("Successed to submitFlyLine2Svr")
                                    completionHandler(true)
                                } else {
                                    print("Failed to submitFlyLine2Svr")
                                    completionHandler(false)
                                }
                            })
                            return
                        }
                        
                    }
                }
            } else {
                print("Failed to screenCapture")
                completionHandler(false)
            }
        })
    }
    
    private func submitFlyLine2Svr(_ imageFile:String, address:String,
                                   province:String, city:String,
                                   district:String, cityCode:String,
                                   completionHandler: @escaping (Bool) -> ()){
        
        let userId:String = "65"
        let missionType:String = "1"
        let urlSubmitFlyLine:String = "/flyline/saveFlyLine?t=1"
        let auth:WebiiAuthSignatureUtil = WebiiAuthSignatureUtil()
        let authedUrl:String = auth.genUrlAuth(url: urlSubmitFlyLine)
        
        let  now =  Date ()
        let  dformatter =  DateFormatter ()
        dformatter.dateFormat =  "yyyy-MM-dd HH:mm:ss"
        let formatedDate = dformatter.string(from: now)
        print ( "当前日期时间：\(formatedDate)" )
         
        //当前时间的时间戳
        let  timeInterval: TimeInterval  = now.timeIntervalSince1970
        let  timeStamp =  Int (timeInterval)
        print ( "当前时间的时间戳：\(timeStamp)" )
        
        struct loc{
            var latitude:Double!
            var longitude:Double!
        }
        
        let center:CLLocationCoordinate2D = Environment.mapViewController.missionPolygon?.center ?? CLLocationCoordinate2D(latitude: 33, longitude: 110)
        let coordinates: [CLLocationCoordinate2D] = Environment.mapViewController.missionPolygon?.coordinates ?? []
        let points: [CLLocationCoordinate2D] = Environment.mapViewController.missionCoordinates()
        
        var para_coords:[loc] = []
        for coord in coordinates {
            para_coords.append(loc(latitude: coord.latitude, longitude: coord.longitude))
        }
        var para_points:[loc] = []
        for coord in points {
            para_points.append(loc(latitude: coord.latitude, longitude: coord.longitude))
        }
        
        let flyLine = ["userId": userId,
                       "name": "航线_123",
                       "boundaryId": "543",
                       "date": formatedDate,
                       "address": "北京市朝阳区",
                       "province": "北京市",
                       "city": "北京市",
                       "district": "朝阳区",
                       "cityCode": "123",
                       "type": missionType,
                       "overlap": "70",
                       "height": "70",
                       "space": "12",
                       "speed": "15",
                       "points": para_points,
                       "imageUrl": imageFile,
                       "cropId": "none",
                       "cropVarietyId": "none",
                       "lat": center.latitude,
                       "lng": center.longitude,
                       "boundary": para_coords,
                       "acreage": "30.2"] as [String : Any]
        HTTP.POST(authedUrl, parameters: flyLine) { response in
            if let err = response.error{
                print ("error: \(err.localizedDescription)")
                completionHandler(false)
                return
            }
            print ("opt finished: \(response.description)")
            let respData:Data! = response.data
            print ("ret: \(String(describing: respData))")
            
            if let json = try? JSONSerialization.jsonObject(with: respData!, options: []) as? [String: Any],
                let code = json["code"] as? String,
                let data = json["data"] as? [[String:Any]]{
                if (code == "000000"){
                    completionHandler(true)
                }else{
                    print (respData ?? "")
                    completionHandler(false)
                }
            }
        }
    }
}
