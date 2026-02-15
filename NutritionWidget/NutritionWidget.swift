import WidgetKit
import SwiftUI
import ActivityKit
struct NutritionWidget: Widget {
    let kind: String = "NutritionWidget"
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NutritionActivityAttributes.self) { context in
            // Lock Screen/Banner UI commented out
            // NutritionLiveActivityView(context: context)
            EmptyView()
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI
                DynamicIslandExpandedRegion(.leading) {
                    Label("\(context.attributes.dailyCalorieGoal)", systemImage: "flame.fill")
                        .font(.caption)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Label("Active", systemImage: "figure.walk")
                        .font(.caption)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text("Nutrition Tracker")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    // Expanded bottom content
                    HStack(spacing: 20) {
                         // Chat Button
                         Link(destination: URL(string: "nutritionapp://chat")!) {
                            Image(systemName: "message.fill")
                                .padding()
                                .background(Color.gray.opacity(0.3))
                                .foregroundColor(.white)
                                .clipShape(Circle())
                        }
                        
                         // Main Open Button
                         Link(destination: URL(string: "nutritionapp://open")!) {
                            Image(systemName: "plus")
                                .padding()
                                .background(Color.orange)
                                .foregroundColor(.black)
                                .clipShape(Circle())
                        }
                        
                        // Data Button
                         Link(destination: URL(string: "nutritionapp://data")!) {
                            Image(systemName: "chart.bar.fill")
                                .padding()
                                .background(Color.gray.opacity(0.3))
                                .foregroundColor(.white)
                                .clipShape(Circle())
                        }
                    }
                    .padding(.top, 8)
                }
            } compactLeading: {
                Image(systemName: "flame.fill")
                    .foregroundColor(.orange)
            } compactTrailing: {
                Text("\(context.state.caloriesRemaining)")
            } minimal: {
                Image(systemName: "flame.fill")
            }
        }
    }
}
struct NutritionLiveActivityView: View {
    let context: ActivityViewContext<NutritionActivityAttributes>
    var body: some View {
        VStack(spacing: 0) {
            // ROW 1: Stats & Progress
            HStack(spacing: 12) {
                // Pulse Icon
                Image(systemName: "waveform.path.ecg")
                    .foregroundColor(.orange)
                    .font(.title2)
                    .padding(8)
                    .background(Circle().fill(Color.white.opacity(0.1)))
                // Progress Bar for Calories
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Calories")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Spacer()
                        Text("\(context.state.caloriesRemaining) kcal left")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .lineLimit(1) // Prevent wrapping
                            .minimumScaleFactor(0.8)
                    }
                    // Removed Progress Line as requested
                }
            }
            .padding(.bottom, 16)
            // ROW 2: ACTION BUTTONS (Chat, Open, Data, Water, SOS)
            HStack {
                // Chat Button
                Link(destination: URL(string: "nutritionapp://chat")!) {
                     Image(systemName: "message.fill")
                        .font(.body)
                        .foregroundColor(.gray)
                        .padding(10)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                
                Spacer()
                
                // Data Button
                Link(destination: URL(string: "nutritionapp://data")!) {
                     Image(systemName: "chart.bar.fill")
                        .font(.body)
                        .foregroundColor(.gray)
                        .padding(10)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                
                Spacer()
                
                // Main Open Button (+)
                Link(destination: URL(string: "nutritionapp://open")!) {
                     Image(systemName: "plus")
                        .font(.title2)
                        .foregroundColor(.black)
                        .padding(12)
                        .background(Circle().fill(Color.orange))
                }
                
                Spacer()
                
                // Water Button
                if #available(iOS 17.0, *) {
                    Button(intent: LogWaterIntent()) {
                        ZStack {
                            Circle()
                                .fill(Color.cyan.opacity(0.2))
                                .frame(width: 44, height: 44)
                            
                            VStack(spacing: 0) {
                                Image(systemName: "drop.fill")
                                    .font(.caption)
                                if context.state.waterIntake > 0 {
                                    Text("\(context.state.waterIntake)")
                                        .font(.system(size: 10, weight: .bold))
                                }
                            }
                            .foregroundColor(.cyan)
                        }
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
                
                // SOS Button
                Link(destination: URL(string: "nutritionapp://sos")!) {
                     Text("SOS")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Circle().fill(Color.red))
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
    }
}
