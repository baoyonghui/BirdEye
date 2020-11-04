//
//  MissionViewController.swift
//  Zond
//
//  Created by Evgeny Agamirzov on 4/6/19.
//  Copyright © 2019 Evgeny Agamirzov. All rights reserved.
//

import os.log
import SwiftHTTP
import DJISDK
import MobileCoreServices
import UIKit

enum MissionState {
    case uploaded
    case running
    case paused
    case editing
}

struct Misson : Codable {
    struct Feature : Codable {
        struct Properties : Codable {
            let distance: Float
            let angle: Float
            let shoot: Float
            let altitude: Float
            let speed: Float
        }

        struct Geometry : Codable {
            let type: String
            let coordinates: [[[Double]]]
        }

        let properties: Properties
        let geometry: Geometry
    }

    let features: [Feature]
}

fileprivate let allowedTransitions: KeyValuePairs<MissionState?,MissionState?> = [
    nil             : .editing,
    .editing        : nil,
    .editing        : .uploaded,
    .uploaded       : .editing,
    .uploaded       : .running,
    .running        : .editing,
    .running        : .paused,
    .paused         : .editing,
    .paused         : .running
]

fileprivate var missionData = TableData([
    /*SectionData(
        id: .command,
        rows: [
            RowData(id: .command,       type: .command, value: MissionState.editing, isEnabled: false)
    ]),*/
    SectionData(
        id: .editor,
        rows: [
            RowData(id: .gridDistance,  type: .slider,  value: Float(10.0),          isEnabled: true) ,
            RowData(id: .gridAngle,     type: .slider,  value: Float(0.0),           isEnabled: true) ,
            RowData(id: .shootDistance, type: .slider,  value: Float(10.0),          isEnabled: true) ,
            RowData(id: .altitude,      type: .slider,  value: Float(50.0),          isEnabled: true) ,
            RowData(id: .flightSpeed,   type: .slider,  value: Float(10.0),          isEnabled: true)
        ]),
])

class MissionViewController : UIViewController {
    // Stored properties
    private var missionView: MissionView!
    private var tableData: TableData = missionData
    private var previousMissionState: MissionState?

    // Observer properties
    private var missionState: MissionState? {
        didSet {
            if allowedTransitions.contains(where: { $0 == oldValue && $1 == missionState }) {
                for listener in stateListeners {
                    listener?(missionState)
                }
            }
        }
    }

    // Notyfier properties
    var stateListeners: [((_ state: MissionState?) -> Void)?] = []
    var logConsole: ((_ message: String, _ type: OSLogType) -> Void)?

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    let dummyData = ["Stark", "Targaeryan", "Boratheon", "Martell", "Lannister", "Tyrell", "Walder Frey"]

    init() {
        super.init(nibName: nil, bundle: nil)
        setUp()
    }
    
    func setUp(){
        missionView = MissionView(tableData.contentHeight)
        missionView.tableView.dataSource = self
        missionView.tableView.delegate = self
        missionView.tableView.register(TableSection.self, forHeaderFooterViewReuseIdentifier: SectionType.spacer.reuseIdentifier)
        missionView.tableView.register(TableCommandCell.self, forCellReuseIdentifier: RowType.command.reuseIdentifier)
        missionView.tableView.register(TableSliderCell.self, forCellReuseIdentifier: RowType.slider.reuseIdentifier)
        //missionView.tableView.register(DoubleButtonTableViewCell.self, forCellReuseIdentifier: identifier)
        registerListeners()
        view = missionView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setUp()
    }
}

// Private methods
extension MissionViewController {
    
    /**
     * 根据表示获取天气类型
     * @param skycon
     * @return
     */
    func getSkycon(_ skycon:String) -> String {
        var resultSky:String = ""
        switch skycon {
            case "CLEAR_DAY":
                resultSky = "晴"
            case "CLEAR_NIGHT":
                resultSky = "晴"
            case "PARTLY_CLOUDY_DAY":
                resultSky = "多云"
            case "PARTLY_CLOUDY_NIGHT":
                resultSky = "多云"
            case "CLOUDY":
                resultSky = "阴"
            case "WIND":
                resultSky = "大风"
            case "HAZE":
                resultSky = "雾霾"
            case "RAIN":
                resultSky = "雨"
            case "SNOW":
                resultSky = "雪"
            default:
                resultSky = ""
        }
        return resultSky
    }
    
    /**
     * 获取小时级别的天气类型
     * @param skycon
     * @param intensity
     * @return
     */
    func getHourWeatherType(skycon:String, intensity:Double) ->String {
        var resultSky:String = getSkycon(skycon)
        if ("雨" == resultSky || "雪" == resultSky) {
            if (intensity < 0.25) {
                resultSky = "小" + resultSky;
            } else if (intensity >= 0.25 && intensity < 0.35) {
                resultSky = "中" + resultSky;
            } else if (intensity >= 0.35 && intensity <= 0.50) {
                resultSky = "大" + resultSky;
            } else {
                resultSky = "暴" + resultSky;
            }
        }
        return resultSky;
    }
    
    /**
     * 获取风力等级   彩云天气返回的数据风速为  公里/小时   需要将值转化为m/s
     * @param temp
     * @return
     */
    func getWindLevel(temp:Double) -> String {
        let windSpeed:Double = temp * 1000 / 3600;
        var windLevel:String
        if (windSpeed >= 0 && windSpeed < 0.3) {
            windLevel = "0级"
        } else if (windSpeed >= 0.3 && windSpeed < 1.6) {
            windLevel = "1级"
        } else if (windSpeed >= 1.6 && windSpeed < 3.4) {
            windLevel = "2级"
        } else if (windSpeed >= 3.4 && windSpeed < 5.5) {
            windLevel = "3级"
        } else if (windSpeed >= 5.5 && windSpeed < 8.0) {
            windLevel = "4级"
        } else if (windSpeed >= 8.0 && windSpeed < 10.8) {
            windLevel = "5级"
        } else if (windSpeed >= 10.8 && windSpeed < 13.9) {
            windLevel = "6级"
        } else if (windSpeed >= 13.9 && windSpeed < 17.2) {
            windLevel = "7级"
        } else if (windSpeed >= 17.2 && windSpeed < 20.8) {
            windLevel = "8级"
        } else if (windSpeed >= 20.8 && windSpeed < 24.5) {
            windLevel = "9级"
        } else if (windSpeed >= 24.5 && windSpeed < 28.5) {
            windLevel = "10级"
        } else if (windSpeed >= 28.5 && windSpeed < 32.7) {
            windLevel = "11级"
        } else {
            windLevel = "12级"
        }
        return windLevel
    }
    
    /**
     * 获取风向，0表示正北方   顺时针
     * @param direction
     * @return
     */
    func getWindDirection(direction:Double) -> String {
        var windDirection:String = ""
        if (direction >= 22.5 && direction < 67.5) {
            windDirection = "东北风"
        } else if (direction >= 67.5 && direction < 112.5) {
            windDirection = "东风"
        } else if (direction >= 112.5 && direction < 157.5) {
            windDirection = "东南风"
        } else if (direction >= 157.5 && direction < 202.5) {
            windDirection = "南风"
        } else if (direction >= 202.5 && direction < 247.5) {
            windDirection = "西南风"
        } else if (direction >= 247.5 && direction < 292.5) {
            windDirection = "西风"
        } else if (direction >= 292.5 && direction < 337.5) {
            windDirection = "西北风"
        } else {
            windDirection = "北风"
        }
        return windDirection
    }
    
    private func submitTask2Svr(_ taskCode:String, count:Int,
                                surveyType:String, surveyContent:String,
                                acreage:Double, boundaryId:String,
                                monitorTime:String, userId:String,
                                startTime:Int, endTime:Int,
                                wind:String, temperature:String,
                                humidity:String, weatherType:String,
                                   completionHandler: @escaping (Bool) -> ()){
        
        let userId:String = "65"
        let missionType:String = "1"
        let urlSubmitTask:String = "/task/uploadTask?code=\(taskCode)&count=\(count)" +
            "&surveyType=\(surveyType)&surveyContent=\(surveyContent)" +
            "&acreage=\(acreage)&boundaryId=\(boundaryId)" +
            "&monitorTime=\(monitorTime)&userId=\(userId)" +
            "&startTime=\(startTime)&endTime=\(endTime)" +
            "&wind=\(wind)&temperature=\(temperature)" +
            "&humidity=\(humidity)&weatherType=\(weatherType)"
        let auth:WebiiAuthSignatureUtil = WebiiAuthSignatureUtil()
        let authedUrl:String = auth.genUrlAuth(url: urlSubmitTask)
        
        HTTP.POST(authedUrl) { response in
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
    
    private func registerListeners() {
        missionView.missionButtonPressed = {
            if self.missionState == nil {
                self.missionState = MissionState.editing
            } else if self.missionState == .editing {
                self.missionState = nil
            }
        }
        Environment.commandService.commandResponded = { id, success in
            if success {
                switch id {
                    case .upload:
                        self.missionState = MissionState.uploaded
                    case .start:
                        self.missionState = MissionState.running
                    case .pause:
                        self.missionState = MissionState.paused
                    case .resume:
                        self.missionState = MissionState.running
                    case .stop:
                        self.missionState = MissionState.editing
                }
            } else {
                self.missionState = MissionState.editing
            }
        }
        // 任务开始时调用
        Environment.commandService.missionStarted = { 
            //self.missionState = MissionState.editing
            // 记录任务开始时间
            let  now =  NSDate ()
            let  timeInterval: TimeInterval  = now.timeIntervalSince1970
            Environment.startTime = Int (timeInterval)
            
            
            
        }
        // 任务完成时调用
        Environment.commandService.missionFinished = { success in
            //self.missionState = MissionState.editing
            // 记录任务结束时间
            let  now =  NSDate ()
            let  timeInterval: TimeInterval  = now.timeIntervalSince1970
            Environment.endTime = Int (timeInterval)
            
            if let center = Environment.mapViewController.missionPolygon?.center {
                let  now =  NSDate ()
                let  timeInterval: TimeInterval  = now.timeIntervalSince1970
                let urlWeather:String = "https://api.caiyunapp.com/v2/3AN0aEo1OyJzrowF/\(center.longitude),\(center.latitude)/weather.jsonp?begin=\(Environment.endTime ?? Int (timeInterval))";
                HTTP.GET(urlWeather) { response in
                    if let err = response.error{
                        print ("error: \(err.localizedDescription)")
                        return
                    }
                    let respData:Data! = response.data
                    if let json = try? JSONSerialization.jsonObject(with: respData!, options: []) as? [String: Any]{
                        let weather:Weather? = Weather(json:json)
                        let weatherType:String = self.getHourWeatherType(skycon:weather?.result?.realtime?.skycon ?? "", intensity:weather?.result?.realtime?.precipitation?.local?.intensity ?? 0)
                        let temperature:String = String.init(format: "%d", weather?.result?.realtime?.temperature ?? 0 + 0.5)
                        let humidity:String = String.init(format: "%d%%", weather?.result?.realtime?.humidity ?? 0 * 100 + 0.5)
                        let precipitation:String = String.init(format:"%fmm", weather?.result?.daily?.precipitation?[0].max ?? 0)
                        let wind:String = self.getWindLevel(temp: weather?.result?.realtime?.wind?.speed ?? 0) + "/" + self.getWindDirection(direction: weather?.result?.realtime?.wind?.direction ?? 0)
                        
                        let temperatureX:TemperatureX? = weather?.result?.daily?.temperature?[1]
                        let temperatureSection:String = String.init(format:"%d～%d", temperatureX?.min ?? 0 + 0.5, temperatureX?.max ?? 0 + 0.5)
                        
                        self.submitTask2Svr("", count:0,
                                            surveyType:"", surveyContent:"",
                                            acreage:10.0, boundaryId:"",
                                            monitorTime:"", userId:"",
                                            startTime:Environment.startTime ?? 0, endTime:Environment.endTime ?? 0,
                                            wind:wind, temperature:temperature,
                                            humidity:humidity, weatherType:weatherType,
                                               completionHandler: { (success:Bool) in
                            if success {
                                print("Successed to submitTask2Svr")
                            } else {
                                print("Failed to submitTask2Svr")
                            }
                        })
                        return
                    }
                }
            }
        }
        Environment.connectionService.listeners.append({ model in
            if model == nil {
                self.tableData.enableRow(at: IdPath(.command, .command), false)
                if self.missionState == .uploaded
                    || self.missionState == .running
                    || self.missionState == .paused {
                    self.missionState = MissionState.editing
                }
            } else {
                self.tableData.enableRow(at: IdPath(.command, .command), true)
                self.tableData.updateRow(at: IdPath(.command, .command), with: MissionState.editing)
            }
        })
        stateListeners.append({ state in
            self.missionView.expand(for: state)
            if state != nil {
                self.tableData.updateRow(at: IdPath(.command, .command), with: state!)
            }
        })
    }

    private func sliderMoved(at idPath: IdPath, to value: Float) {
        tableData.updateRow(at: idPath, with: value)
        switch idPath{
            case IdPath(.editor, .gridDistance):
                Environment.mapViewController.missionPolygon?.gridDistance = CGFloat(value)
                Environment.commandService.missionParameters.turnRadius = (Float(value) / 2) - 10e-6
            case IdPath(.editor, .gridAngle):
                Environment.mapViewController.missionPolygon?.gridAngle = CGFloat(value)
            case IdPath(.editor, .altitude):
                Environment.commandService.missionParameters.altitude = Float(value)
            case IdPath(.editor, .shootDistance):
                Environment.commandService.missionParameters.shootDistance = Float(value)
            case IdPath(.editor, .flightSpeed):
                Environment.commandService.missionParameters.flightSpeed = Float(value)
            default:
                break
        }
    }

    private func buttonPressed(with id: CommandButtonId) {
        switch id {
            case .importJson:
                print ("here importJson")
                let documentPicker = UIDocumentPickerViewController(documentTypes: [String(kUTTypeJSON)], in: .import)
                documentPicker.delegate = self
                //documentPicker.shouldShowFileExtensions = true
                //documentPicker.allowsMultipleSelection = false
                Environment.rootViewController.present(documentPicker, animated: true, completion: nil)
            case .upload:
                print ("here 0")
                let coordinates = Environment.mapViewController.missionCoordinates()
                if Environment.commandService.setMissionCoordinates(coordinates) {
                    print ("here 1")
                    Environment.commandService.executeMissionCommand(.upload)
                }
            case .start:
                Environment.commandService.executeMissionCommand(.start)
            case .edit:
                self.missionState = MissionState.editing
            case .pause:
                Environment.commandService.executeMissionCommand(.pause)
            case .resume:
                Environment.commandService.executeMissionCommand(.resume)
            case .stop:
                Environment.commandService.executeMissionCommand(.stop)
        }
    }

    private func commandCell(for rowData: RowData<Any>, at indexPath: IndexPath, in tableView: UITableView) -> TableCommandCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: rowData.type.reuseIdentifier, for: indexPath) as! TableCommandCell
        cell.buttonPressed = { id in
            self.buttonPressed(with: id)
        }
        rowData.updated = {
            cell.updateData(rowData)
        }
        //cell.buttonDelegate = self
        return cell
    }

    private func sliderCell(for rowData: RowData<Any>, at indexPath: IndexPath, in tableView: UITableView) -> TableSliderCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: rowData.type.reuseIdentifier, for: indexPath) as! TableSliderCell

        // Slider default values in the data source should be delivered to the
        // respective components upon creation, thus simulate slider "move" to the
        // initial value which will notify a subscriber of the respective parameter.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.sliderMoved(at: IdPath(.editor, rowData.id), to: rowData.value as! Float)
        }

        cell.sliderMoved = { id , value in
            self.sliderMoved(at: id, to: value)
        }
        rowData.updated = {
            cell.updateData(rowData)
        }
        return cell
    }
}

// Table view data source
extension MissionViewController : UITableViewDataSource {
    internal func numberOfSections(in tableView: UITableView) -> Int {
        return tableData.sections.count
    }

    internal func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return tableData.sections[section].rows.count
    }

    internal func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var cell: UITableViewCell!
        let rowData = tableData.rowData(at: indexPath)
        switch rowData.type {
            case .command:
                cell = commandCell(for: rowData, at: indexPath, in: tableView)
                /*
                let result = tableView.dequeueReusableCell(withIdentifier: identifier, for: indexPath)
                if let cell2 = result as? DoubleButtonTableViewCell {
                    
                    var text = "No Title"
                    if indexPath.row < dummyData.count {
                        text = dummyData[indexPath.row]
                        cell2.color = indexPath.row % 3 == 0 ? UIColor.lightGray : UIColor.darkGray
                        cell2.load(text: text, indexPath: indexPath, buttonDelegate: self, leftButtonImage: UIImage(named:"clearButton"), rightButtonImage: UIImage(named:"rightCircleCarat"))
                        
                    }
                    return cell2
                }*/
            case .slider:
                cell = sliderCell(for: rowData, at: indexPath, in: tableView)
        }
        rowData.updated?()
        return cell
    }

}

// Table view apperance
extension MissionViewController : UITableViewDelegate {
    internal func tableView(_ tableView: UITableView, heightForRowAt: IndexPath) -> CGFloat {
        return tableData.rowHeight
    }

    internal func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return tableData.sections[section].id.headerHeight
    }

    internal func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return tableData.sections[section].id.footerHeight
    }

    internal func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        return missionView.tableView.dequeueReusableHeaderFooterView(withIdentifier: SectionType.spacer.reuseIdentifier) as! TableSection
    }

    internal func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        return missionView.tableView.dequeueReusableHeaderFooterView(withIdentifier: SectionType.spacer.reuseIdentifier) as! TableSection
    }
}

// Document picker updates
extension MissionViewController : UIDocumentPickerDelegate {
    internal func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if let jsonUrl = urls.first {
            do {
                let jsonFile = try String(contentsOf: jsonUrl, encoding: .utf8)
                do {
                    let jsonData = jsonFile.data(using: .utf8)!
                    let decoder = JSONDecoder()
                    let mission = try decoder.decode(Misson.self, from: jsonData).features[0]

                    sliderMoved(at: IdPath(.editor, .gridDistance), to: mission.properties.distance)
                    sliderMoved(at: IdPath(.editor, .gridAngle), to: mission.properties.angle)
                    sliderMoved(at: IdPath(.editor, .shootDistance), to: mission.properties.shoot)
                    sliderMoved(at: IdPath(.editor, .altitude), to: mission.properties.altitude)
                    sliderMoved(at: IdPath(.editor, .flightSpeed), to: mission.properties.speed)

                    if mission.geometry.type == "Polygon"  && !mission.geometry.coordinates.isEmpty {
                        // First element of the geometry is always the outer polygon
                        var rawCoordinates = mission.geometry.coordinates[0]
                        rawCoordinates.removeLast()
                        Environment.mapViewController.showMissionPolygon(rawCoordinates)
                    }
                } catch {
                    logConsole?("JSON parse error: \(error)", .error)
                }
            } catch {
                logConsole?("JSON read error: \(error)", .error)
            }
        }
    }
}
