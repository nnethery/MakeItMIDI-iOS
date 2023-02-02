//
//  ContentView.swift
//  MakeItMIDI
//
//  Created by Noah Nethery on 11/17/22.
//

import SwiftUI
import MIDIKitIO
import Matft

let numberOfSamples: Int = 20

struct ContentView: View {
    @State var isRecording = false
    @State var useViterbiDecoding = false
    @State var sliderValue: Double = 0.5
    @ObservedObject private var audioInput = AudioInputManager(sampleRate: 16000)
    @State private var drawingHeight = true
    @State var predictVelocities = false
    
    @EnvironmentObject var midiManager: MIDIManager
    
    var outputConnection: MIDIOutputConnection? {
        midiManager.managedOutputConnections[MakeItMIDIApp.outputConnectionName]
    }
    
    let soundClassifier = SoundClassifier(modelFileName: "onsets_frames_wavinput")
    
    var body: some View {
        VStack {
            Text("Instrument:").fontWeight(.regular).font(.title3)
            Menu {
                Button {
                    // do something
                } label: {
                    Text("Piano")
                }
            } label: {
                Text("Piano")
            }
            HStack(spacing: 4) {
                ForEach(0..<20) { number in
                    BarView(value: CGFloat(self.audioInput.viz[number]))
                }
                
            }
            .frame(height: 200)
            Button(action: {
                if (!isRecording) {
                    audioInput.checkPermissionsAndStartTappingMicrophone()
                } else {
                    audioInput.stopTappingMicrophone()
                }
                isRecording = !isRecording
            }) {
                if (!isRecording) {
                    HStack {
                        Text("Start").fontWeight(.semibold).font(.title)
                    }
                    .padding()
                    .foregroundColor(.white)
                    .background(Color.blue)
                    .cornerRadius(40)
                } else {
                    HStack {
                        Text("Stop").fontWeight(.semibold).font(.title)
                    }
                    .padding()
                    .foregroundColor(.white)
                    .background(Color.red)
                    .cornerRadius(40)
                }
            }
            HStack() {
                Text("Predict Velocities")
                Spacer()
                Toggle("Predict Velocities", isOn: $predictVelocities).labelsHidden()
            }
            .padding(10)
            HStack() {
                if (!useViterbiDecoding) {
                    Text("Wrong-Note Filter")
                } else {
                    Text("Wrong-Note Filter, α = \(sliderValue, specifier: "%.1f")")
                }
                Spacer()
                Toggle("Wrong-Note Filter", isOn: $useViterbiDecoding).labelsHidden()
            }
            .padding(10)
            if (useViterbiDecoding) {
                Slider(value: $sliderValue, in: 0...1, step: 0.1).padding(10)
            }
//            Button(action: showHelp) {
//                Label("Help", systemImage: "questionmark.circle.fill")
//            }.padding(20)
        }.onReceive(self.audioInput.$samples) { audioSamples in
            //            let startTime = CFAbsoluteTimeGetCurrent()
            let noteSequence = soundClassifier.start(inputBuffer: audioSamples, predictVelocities: predictVelocities, viterbiDecoding: useViterbiDecoding, viterbiThreshold: sliderValue)
            //            let endTime = CFAbsoluteTimeGetCurrent()
            //            let timeElapsed = endTime - startTime
            //            print("Time elapsed for prediction: \(Int(timeElapsed * 1000)) ms.")
            noteSequence.forEach { note in
                do {
                    try outputConnection?.send(event: .noteOn(
                        UInt7(note.pitch + 21),
                        velocity: .midi1(UInt7(note.velocity)),
                        channel: 0x0,
                        midi1ZeroVelocityAsNoteOff: false
                    ))
                } catch let error {
                    print(error)
                }
            }
        }
    }
    
    func showHelp() {
        
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

struct BarView: View {
    var value: CGFloat
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(LinearGradient(gradient: Gradient(
                    colors: [.purple, .blue]),
                                     startPoint: .top,
                                     endPoint: .bottom))
                .frame(width: (UIScreen.main.bounds.width - CGFloat(numberOfSamples) * 4) / CGFloat(numberOfSamples), height: value)
        }
    }
}
