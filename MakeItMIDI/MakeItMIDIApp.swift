//
//  MakeItMIDIApp.swift
//  MakeItMIDI
//
//  Created by Noah Nethery on 11/17/22.
//

import SwiftUI
import MIDIKitIO

@main
struct MakeItMIDIApp: App {
    let midiManager = MIDIManager(
        clientName: "MIMMIDIManager",
        model: "MakeItMIDI iOS",
        manufacturer: "MakeItMIDI"
    )
    
    static let inputConnectionName = "MakeItMIDI iOS Input Connection"
    static let outputConnectionName = "MakeItMIDI iOS Output Connection"
    
    init() {
        do {
            print("Starting MIDI services.")
            try midiManager.start()
        } catch {
            print(error.self)
            print("Error starting MIDI services:", error.localizedDescription)
        }
        
        do {
            print("Creating MIDI input connection.")
            try midiManager.addInputConnection(
                toOutputs: [.name("IDAM MIDI Host")],
                tag: Self.inputConnectionName,
                receiver: .eventsLogging()
            )
            
            print("Creating MIDI output connection.")
            try midiManager.addOutputConnection(
                toInputs: [.name("IDAM MIDI Host")],
                tag: Self.outputConnectionName
            )
        } catch {
            print(error.self)
            print("Error creating virtual MIDI output:", error.localizedDescription)
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(midiManager)
        }
    }
}
