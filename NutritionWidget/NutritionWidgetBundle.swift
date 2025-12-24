//
//  NutritionWidgetBundle.swift
//  NutritionWidget
//
//  Created by Ishwar Partap Singh on 18/12/25.
//

import WidgetKit
import SwiftUI

@main
struct NutritionWidgetBundle: WidgetBundle {
    var body: some Widget {
        NutritionWidget()
        NutritionWidgetControl()
        NutritionWidgetLiveActivity()
    }
}
