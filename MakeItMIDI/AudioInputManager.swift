//
//  AudioInputManager.swift
//  MakeItMIDI
//
//  Created by Noah Nethery on 11/17/22.
//

import Foundation
import AVFoundation
import Accelerate

class AudioInputManager: ObservableObject {
    public let bufferSize: Int
    @Published public var samples: [Int16] = Array(repeating: 0, count: 17920)
    @Published public var viz: [Float] = Array(repeating: 1, count: 20)
    
    private let sampleRate: Int
    private let conversionQueue = DispatchQueue(label: "conversionQueue")
    
    private var audioEngine = AVAudioEngine()
    private var timer: Timer?
    private var currentSample = 0
    private var overlap: [Int16]?
    
    var prevRMSValue : Float = 0.3
    let fftSetup = vDSP_DFT_zop_CreateSetup(nil, 1024, vDSP_DFT_Direction.FORWARD)
    
    public init(sampleRate: Int) {
        self.sampleRate = sampleRate
        let padding = 1920
        //        let padding = 0
        self.bufferSize = (sampleRate + padding) * 1
    }
    
    public func checkPermissionsAndStartTappingMicrophone() {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            startTappingMicrophone()
        case .denied:
            print("Denied")
            //            delegate?.audioInputManagerDidFailToAchievePermission(self)
        case .undetermined:
            requestPermissions()
        @unknown default:
            fatalError()
        }
    }
    
    public func stopTappingMicrophone() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        self.viz = Array(repeating: 1, count: 20)
    }
    
    public func requestPermissions() {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            if granted {
                self.startTappingMicrophone()
            } else {
                self.checkPermissionsAndStartTappingMicrophone()
            }
        }
    }
    
    public func startTappingMicrophone() {
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard let recordingFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(sampleRate),
            channels: 1,
            interleaved: true
        ), let formatConverter = AVAudioConverter(from:inputFormat, to: recordingFormat) else { return }
        
        // installs a tap on the audio engine and specifying the buffer size and the input format.
        //        inputNode.installTap(onBus: 1, bufferSize: AVAudioFrameCount(bufferSize), format: inputNode.outputFormat(forBus: 1)) {
        //            buffer, _ in
        //
        //        }
        
        inputNode.installTap(onBus: 0, bufferSize: AVAudioFrameCount(bufferSize), format: inputFormat) {
            buffer, _ in
            //            print(t)
            
            DispatchQueue.main.async {
                // An AVAudioConverter is used to convert the microphone input to the format required
                // for the model.(pcm 16)
                guard let pcmBuffer = AVAudioPCMBuffer(
                    pcmFormat: recordingFormat,
                    frameCapacity: AVAudioFrameCount(self.bufferSize)
                ) else { return }
                
                var error: NSError?
                let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                    outStatus.pointee = AVAudioConverterInputStatus.haveData
                    return buffer
                }
                
                formatConverter.convert(to: pcmBuffer, error: &error, withInputFrom: inputBlock)
                
                if let error = error {
                    print(error.localizedDescription)
                    return
                }
                
                if let channelData = pcmBuffer.int16ChannelData {
                    let channelDataValue = channelData.pointee
                    let channelDataValueArray = stride(
                        from: 0,
                        to: Int(pcmBuffer.frameLength),
                        by: buffer.stride
                    ).map { channelDataValue[$0] }
                    
                    let dd = channelDataValueArray.compactMap {Float($0)}
                    let rms = 10 * log10f(vDSP.rootMeanSquare(dd))
                    
                    //                    let amp = SignalProcessing.rms(data: channelDataValue, frameLength: UInt(pcmBuffer.frameLength))
                    
                    self.viz = self.insertIntoArray(rms * 2, array: self.viz)
                    
                    self.samples = channelDataValueArray
                    
                    if let _ = self.overlap {
                        //                        self.samples = sampleOverlap + channelDataValueArray[sampleOverlap.count..<self.sampleRate]
                    }
                    
                    // TODO: Could result in a delay of 1 second in prediction
                    self.overlap = Array(channelDataValueArray[self.sampleRate..<self.bufferSize])
                }
            }
        }
        
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            print(error.localizedDescription)
        }
    }
    
    func processAudioData(buffer: AVAudioPCMBuffer) {
        //        guard let channelData = buffer.floatChannelData?[0] else {return}
        //        let frames = buffer.frameLength
        
        //        let rmsValue = SignalProcessing.rms(data: channelData, frameLength: UInt(frames))
        //        let interpolatedResults = SignalProcessing.interpolate(point1: prevRMSValue, point2: rmsValue, num: 7)
        //        prevRMSValue = rmsValue
        //
        //        //fft
        //        let fftMagnitudes =  SignalProcessing.fft(data: channelData, setup: fftSetup!)
    }
    
    func insertIntoArray(_ value: Float, array: [Float]) -> [Float] {
        var arr = array
        if arr.count == 20 {
            arr.removeFirst()
        }
        arr.append(value)
        return arr
    }
}
