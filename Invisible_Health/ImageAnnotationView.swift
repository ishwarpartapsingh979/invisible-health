//
//  ImageAnnotationView.swift
//  Invisible_Health
//
//  Created by Ishwar Partap Singh on 26/01/26.
//

import SwiftUI

struct ImageAnnotationView: View {
    let image: UIImage
    var onSend: (String) -> Void
    var onCancel: () -> Void
    
    @State private var caption: String = ""
    @FocusState private var isFocused: Bool
    
    var body: some View {
        NavigationView {
            VStack {
                Spacer()
                
                // Image Preview
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 400)
                    .cornerRadius(12)
                    .shadow(radius: 10)
                    .padding()
                
                Spacer()
                
                // Caption Input
                HStack {
                    TextField("Add a caption... (e.g. Lunch at office)", text: $caption)
                        .padding()
                        .background(Color(UIColor.systemGray6))
                        .cornerRadius(20)
                        .focused($isFocused)
                    
                    Button(action: {
                        onSend(caption)
                    }) {
                        Image(systemName: "paperplane.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.blue)
                            .clipShape(Circle())
                    }
                }
                .padding()
            }
            .navigationBarTitle("Log Food", displayMode: .inline)
            .navigationBarItems(leading: Button("Cancel") {
                onCancel()
            })
            .onAppear {
                isFocused = true
            }
        }
    }
}
