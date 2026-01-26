//
//  EditLogView.swift
//  Invisible_Health
//
//  Created by Agent on Phase 2 Refinement.
//

import SwiftUI

struct EditLogView: View {
    let log: AgentManager.NutritionLog
    let onSave: (AgentManager.NutritionLog) -> Void
    @Environment(\.presentationMode) var presentationMode
    
    @State private var name: String
    @State private var calories: String
    @State private var protein: String
    @State private var carbs: String
    @State private var fat: String
    
    init(log: AgentManager.NutritionLog, onSave: @escaping (AgentManager.NutritionLog) -> Void) {
        self.log = log
        self.onSave = onSave
        _name = State(initialValue: log.food_name)
        _calories = State(initialValue: String(format: "%.0f", log.calories ?? 0))
        _protein = State(initialValue: String(format: "%.0f", log.protein ?? 0))
        _carbs = State(initialValue: String(format: "%.0f", log.carbs ?? 0))
        _fat = State(initialValue: String(format: "%.0f", log.fats ?? 0))
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Food Details")) {
                    TextField("Name", text: $name)
                    HStack {
                        Text("Calories")
                        Spacer()
                        TextField("0", text: $calories)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                Section(header: Text("Macros (Grams)")) {
                    HStack {
                        Text("Protein")
                        Spacer()
                        TextField("0", text: $protein)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Carbs")
                        Spacer()
                        TextField("0", text: $carbs)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Fats")
                        Spacer()
                        TextField("0", text: $fat)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                Section {
                    Button("Delete Log") {
                        // Future: Implement Delete
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("Edit Log")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                }
            }
        }
    }
    
    func save() {
        // Create Updated Log
        let updatedLog = AgentManager.NutritionLog(
            id: log.id,
            food_name: name,
            calories: Double(calories),
            protein: Double(protein),
            carbs: Double(carbs),
            fats: Double(fat),
            message: log.message,
            created_at: log.created_at
        )
        
        // 1. Update UI via Callback
        onSave(updatedLog)
        
        // 2. Fire Backend Update (Fire and forget)
        AgentManager.shared.updateLog(updatedLog)
        
        presentationMode.wrappedValue.dismiss()
    }
}
