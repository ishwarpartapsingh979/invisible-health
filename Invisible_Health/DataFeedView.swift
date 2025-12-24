//
//  DataFeedView.swift
//  Invisible_Health
//
//  Created by Ishwar Partap Singh on 23/12/25.
//

import SwiftUI
struct DataFeedView: View {
    // Sample Data
    @State private var items = [
        ("Salmon & Rice Bowl", "650 kcal - 45g Protein", "Today, 12:30 PM"),
        ("Oatmeal & Berries", "320 kcal - 12g Protein", "Today, 8:00 AM"),
        ("Protein Shake", "180 kcal - 25g Protein", "Yesterday, 9:00 PM")
    ]
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Your Log")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding()
            
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(0..<items.count, id: \.self) { index in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(items[index].0)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                Text(items[index].1)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            Text(items[index].2)
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        .padding()
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
            }
        }
        .background(Color.black)
    }
}
