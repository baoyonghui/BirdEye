//
//  RootView.swift
//  Zond
//
//  Created by Evgeny Agamirzov on 4/25/19.
//  Copyright © 2019 Evgeny Agamirzov. All rights reserved.
//

import UIKit

class FlyLineView : UIView {
    
    // Computed properties
    private var width: CGFloat {
        return Dimensions.ContentView.width * (Dimensions.ContentView.Ratio.h[0] + Dimensions.ContentView.Ratio.h[1])
               - Dimensions.viewSpacer
    }
    private var height: CGFloat {
        return Dimensions.ContentView.height * Dimensions.ContentView.Ratio.v[0]
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    init() {
        super.init(frame: CGRect(
            x: 0,
            y: 0,
            width: Dimensions.screenWidth,
            height: Dimensions.screenHeight
        ))
        addSubview(Environment.mapViewController.view)
        addSubview(Environment.consoleViewController.view)
        addSubview(Environment.missionViewController.view)
        addSubview(Environment.navigationViewController.view)
        addSubview(Environment.statusViewController.view)
        let frame = CGRect(
            x: Dimensions.ContentView.x,
            y: Dimensions.ContentView.y,
            width: width,
            height: height
        )
        Environment.statusViewController.view.frame = frame
    }
}
