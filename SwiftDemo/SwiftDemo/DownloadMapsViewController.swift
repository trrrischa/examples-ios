//
//  DownloadMapsViewController.swift
//  GLMap
//
//  Created by Evgen Bodunov on 11/28/16.
//  Copyright © 2016 Evgen Bodunov. All rights reserved.
//

import UIKit
import GLMap
import GLMapSwift

class DownloadMapsViewController: UITableViewController {

    var mapsOnDevice: [GLMapInfo] = [], mapsOnServer: [GLMapInfo] = [], allMaps: [GLMapInfo] = []

    override func viewWillAppear(_ animated: Bool) {
        if allMaps.count == 0 { // map data could be set during preparing for segue
            if let cachedMapList = GLMapManager.shared().cachedMapList() {
                setMaps(cachedMapList)
            }
            updateMaps()
        }

        NotificationCenter.default.addObserver(self, selector: #selector(DownloadMapsViewController.mapUpdated), name: GLMapInfo.stateChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(DownloadMapsViewController.progressUpdated), name: GLMapInfo.downloadProgress, object: nil)
    }

    func updateMaps() {
        GLMapManager.shared().updateMapList { (fetchedMaps: [GLMapInfo]?, _, error: Error?) in
            if error != nil {
                NSLog("Map downloading error \(error!.localizedDescription)")
            } else {
                if let maps = fetchedMaps {
                    self.setMaps(maps)
                }
            }
        }
    }

    func mapUpdated(notification: Notification) {
        setMaps(allMaps)
    }

    func progressUpdated(notification: Notification) {
        if let map = notification.object as? GLMapInfo {
            updateCellForMap(map)
        }
    }

    func updateCellForMap(_ map: GLMapInfo) {
        if let index = mapsOnDevice.index(of: map) {
            tableView.reloadRows(at: [IndexPath.init(row: index, section: 0)], with: .none)
        } else {
            setMaps(allMaps)
        }
    }

    func setMaps(_ maps: [GLMapInfo]) {
        // Unroll map groups for Africa, Caribbean, and Oceania
        // maps = [self unrollMapArray:maps];

        // Detect and pass user location there. If there is no location detected yet, just don't sort an array by location. ;)
        let userLocation = GLMapGeoPoint.init(lat: 40.7, lon: -73.9)

        let sortedMaps = sort(maps: maps, byDistanceFrom: userLocation)
        // let sortedMaps = sort(maps: maps, byNameIn: "en")
        
        allMaps = sortedMaps

        mapsOnDevice.removeAll()
        mapsOnServer.removeAll()

        for mapInfo in allMaps {
            let subMaps = mapInfo.subMaps;
            
            if (subMaps.count != 0){
                var downloadedSubMaps = 0

                for subInfo in subMaps {
                    if (subInfo.state > .notDownloaded) {
                        downloadedSubMaps = downloadedSubMaps + 1
                    }
                }

                if downloadedSubMaps > 0 {
                    mapsOnDevice.append(mapInfo)
                }
                if downloadedSubMaps != subMaps.count {
                    mapsOnServer.append(mapInfo)
                }
            } else if mapInfo.state == .notDownloaded {
                mapsOnServer.append(mapInfo)
            } else {
                mapsOnDevice.append(mapInfo)
            }
        }

        self.tableView.reloadData()
    }

    func sort(maps: [GLMapInfo], byDistanceFrom location: GLMapGeoPoint) -> [GLMapInfo] {
        return maps.sorted(by: { (a: GLMapInfo, b: GLMapInfo) -> Bool in
            return a.distance(from: location) < b.distance(from: location)
        })
    }

    func sort(maps: [GLMapInfo], byNameIn locale: String) -> [GLMapInfo] {
        return maps.sorted(by: { (a: GLMapInfo, b: GLMapInfo) -> Bool in
            var aName = a.name(inLanguage: locale)
            if aName == nil {
                aName = a.name()
            }

            var bName = b.name(inLanguage: locale)
            if bName == nil {
                bName = b.name()
            }

            if aName != nil && bName != nil {
                return aName! < bName!
            }

            return false
        })
    }

    // MARK: Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 0 {
            return "Maps on device"
        } else {
            return "Maps on server"
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            return mapsOnDevice.count
        } else {
            return mapsOnServer.count
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        let identifier = "MapCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier, for: indexPath)

        let mapInfo: GLMapInfo
        if indexPath.section == 0 {
            mapInfo = mapsOnDevice[indexPath.row]

            if mapInfo.subMaps.count > 0 {
                cell.accessoryType = .disclosureIndicator
                cell.detailTextLabel?.text = nil
            } else {
                cell.accessoryType = .none

                switch mapInfo.state {
                case .needUpdate:
                    cell.detailTextLabel?.text = "Update"
                case .needResume:
                    cell.detailTextLabel?.text = "Resume"
                case .downloaded:
                    cell.accessoryView = nil
                    cell.detailTextLabel?.text = String.init(format: "%.2f MB", Double(mapInfo.sizeOnDisk) / 1000000)
                case .inProgress:
                    cell.detailTextLabel?.text = String.init(format: "Downloading %.2f%%", mapInfo.downloadProgress*100)
                case .notDownloaded:
                    cell.detailTextLabel?.text = nil
                default:
                    break
                }
            }
        } else {
            mapInfo = mapsOnServer[indexPath.row]

            if mapInfo.subMaps.count > 0 {
                cell.accessoryType = .disclosureIndicator
                cell.detailTextLabel?.text = nil
            } else {
                cell.accessoryType = .none
                cell.detailTextLabel?.text = String.init(format: "%.2f MB", Double(mapInfo.sizeOnServer) / 1000000)
            }
        }

        cell.textLabel?.text = mapInfo.name()
        //cell.detailTextLabel?.text = row.description

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let mapInfo: GLMapInfo
        if indexPath.section == 0 {
            mapInfo = mapsOnDevice[indexPath.row]
        } else {
            mapInfo = mapsOnServer[indexPath.row]
        }

        if mapInfo.subMaps.count > 0 {
            performSegue(withIdentifier: "OpenSubmap", sender: mapInfo)
        } else {
            if mapInfo.state != .downloaded {
                if let downloadTask = GLMapManager.shared().downloadTask(forMap: mapInfo) {
                    downloadTask.cancel()
                } else {
                    startDownloadingMap(mapInfo, retryCount: 3)
                }
            }
        }

        tableView.deselectRow(at: indexPath, animated: true)
    }

    func startDownloadingMap(_ map: GLMapInfo, retryCount: Int) {
        if retryCount > 0 {
            GLMapManager.shared().downloadMap(map, withCompletionBlock: { (task: GLMapDownloadTask) in
                if let error = task.error as NSError? {
                    NSLog("Map downloading error: \(error)")
                    //CURLE_OPERATION_TIMEDOUT = 28 http://curl.haxx.se/libcurl/c/libcurl-errors.html
                    if error.domain == "CURL" && error.code == 28 {
                        self.startDownloadingMap(map, retryCount: 2)
                    }
                }
            })
        }
    }

    /*
    -(void) prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if([segue.identifier isEqualToString:@"openSubmap"]) {
    DownloadMapsViewController *vc = (DownloadMapsViewController*)segue.destinationViewController;
    GLMapInfo *map = sender;
    vc.title = [map nameInLanguage:@"en"];
    [vc setMaps:map.subMaps];
    }
    }
    */

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "OpenSubmap" {
            if let mapViewController = segue.destination as? DownloadMapsViewController {
                if let map = sender as? GLMapInfo {
                    mapViewController.setMaps(map.subMaps)
                    mapViewController.title = map.name()
                }
            }
        }
    }

    override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCellEditingStyle {
        if indexPath.section == 0 {
            let map = mapsOnDevice[indexPath.row]

            if map.subMaps.count == 0 {
                return .delete
            }
        }
        return .none
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let map = mapsOnDevice[indexPath.row]

            GLMapManager.shared().deleteMap(map)
            setMaps(allMaps)
        }
    }
}
