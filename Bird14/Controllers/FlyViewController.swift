//
//  RootViewController.swift
//  Zond
//
//  Created by Evgeny Agamirzov on 4/24/19.
//  Copyright © 2019 Evgeny Agamirzov. All rights reserved.
//

import UIKit

class FlyLineViewController : UIViewController {
    private var rootView: FlyLineView!
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    // call by programm init
    init() {
        super.init(nibName: nil, bundle: nil)
        print ("init")
        rootView = FlyLineView()
        view = rootView
    }
    
    // call by storyboard init
    override func viewDidLoad() {
        super.viewDidLoad()
        rootView = FlyLineView()
        view = rootView
    }
}
