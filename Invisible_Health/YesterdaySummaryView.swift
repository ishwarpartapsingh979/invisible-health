//
//  YesterdaySummaryView.swift
//  Invisible_Health
//
//  Created by Ishwar Partap Singh on 22/12/25.
//

import SwiftUI
struct YesterdaySummaryView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var notificationManager: NotificationManager
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Yesterday's Summary")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("You did great!")
                    .font(.title2)
                
                Spacer()
                
                Button(action: {
                    // Start Live Activity when closing
                    notificationManager.startLiveActivity()
                    dismiss()
                }) {
                    Text("Close & Start Day")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .padding()
            }
            .padding()
            .navigationTitle("Summary")
        }
    }
}
