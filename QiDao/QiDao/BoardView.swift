import SwiftUI

struct BoardView: View {
    @StateObject private var viewModel = BoardViewModel()
    
    var body: some View {
        VStack(spacing: 20) {
            Text("QiDao Board")
                .font(.largeTitle)
            
            // Simple 19x19 grid representation
            ZStack {
                Color(red: 0.8, green: 0.6, blue: 0.4) // Wood color
                
                VStack(spacing: 0) {
                    ForEach(0..<19, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<19, id: \.self) { col in
                                Rectangle()
                                    .stroke(Color.black, lineWidth: 0.5)
                                    .frame(width: 20, height: 20)
                            }
                        }
                    }
                }
            }
            .frame(width: 380, height: 380)
            .border(Color.black, width: 2)
            
            VStack {
                Text(viewModel.message)
                Text(viewModel.gameInfo)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Button("Test Rust Core") {
                viewModel.testCore()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

#Preview {
    BoardView()
}
