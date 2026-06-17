//
//  ThinkWidgetsBundle.swift
//  ThinkWidgets
//
//  Created by Christian Matsoukis on 6/16/26.
//

import WidgetKit
import SwiftUI

@main
struct ThinkWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ThinkWidgets()
        ThinkWidgetsLiveActivity()
    }
}
