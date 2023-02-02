//
//  Note.swift
//  MakeItMIDI
//
//  Created by Noah Nethery on 12/31/22.
//

import Foundation

public class Note: CustomStringConvertible {
    public var description: String {
        var note: String
        
        switch pitch % 12 {
        case 0:
            note = "A"
        case 1:
            note = "A#"
        case 2:
            note = "B"
        case 3:
            note = "C"
        case 4:
            note = "C#"
        case 5:
            note = "D"
        case 6:
            note = "D#"
        case 7:
            note = "E"
        case 8:
            note = "F"
        case 9:
            note = "F#"
        case 10:
            note = "G"
        case 11:
            note = "G#"
        default:
            note = "Unknown"
        }
        
        return "\(note)\(Int(pitch / 12)): \(velocity)>> \(startTime)-\(endTime)"
    }
    
    public var pitch: Int32
    public var startTime: Double
    public var endTime: Double
    public var velocity: Int32
    public var instrument: Int32 = 0
    public var program: Int32 = 0
    
    public init(pitch: Int32, startTime: Double, endTime: Double, velocity: Int32) {
        self.pitch = pitch
        self.startTime = startTime
        self.endTime = endTime
        self.velocity = velocity
    }
}
