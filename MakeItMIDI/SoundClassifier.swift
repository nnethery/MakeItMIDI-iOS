//
//  SoundClassifier.swift
//  MakeItMIDI
//
//  Created by Noah Nethery on 11/23/22.
//

import Foundation
import TensorFlowLite
import Matft

class SoundClassifier: ObservableObject {
    // MARK: - Constants
    private let modelFileName: String
    private let modelFileExtension: String
    private let audioBufferInputTensorIndex: Int = 0
    
    private(set) var sampleRate = 16000
    private var interpreter: Interpreter!
    
    public init(
        modelFileName: String,
        modelFileExtension: String = "tflite"
    ) {
        self.modelFileName = modelFileName
        self.modelFileExtension = modelFileExtension
        
        setupInterpreter()
    }
    
    private func setupInterpreter() {
        guard let modelPath = Bundle.main.path(
            forResource: modelFileName,
            ofType: modelFileExtension
        ) else { return }
        
        
        var options = CoreMLDelegate.Options()
        options.coreMLVersion = 3
        options.enabledDevices = .all
        do {
            let coreMLDelegate: CoreMLDelegate? = CoreMLDelegate(options: options)
            if coreMLDelegate != nil {
                interpreter = try Interpreter(modelPath: modelPath, delegates: [])
                print("Using CoreML delegate")
            } else {
                interpreter = try Interpreter(modelPath: modelPath)
                print("Using CPU inference")
            }
            try interpreter.allocateTensors()
            print("loading model")
            
            try interpreter.invoke()
            
        } catch {
            print("Failed to create the interpreter with error: \(error.localizedDescription)")
            return
        }
    }
    
    public func start(inputBuffer: [Int16], predictVelocities: Bool, viterbiDecoding: Bool, viterbiThreshold: Double) -> [Note] {
        let framesOutputTensor: Tensor
        let onsetsOutputTensor: Tensor
        let offsetsOutputTensor: Tensor
        let velocitiesOutputTensor: Tensor
        do {
            let audioBufferData = int16ArrayToData(inputBuffer)
            try interpreter.copy(audioBufferData, toInputAt: audioBufferInputTensorIndex)
            try interpreter.invoke()
            
            framesOutputTensor = try interpreter.output(at: 0)
            onsetsOutputTensor = try interpreter.output(at: 1)
            offsetsOutputTensor = try interpreter.output(at: 2)
            velocitiesOutputTensor = try interpreter.output(at: 3)
        } catch let error {
            print(">>> Failed to invoke the interpreter with error: \(error.localizedDescription)")
            return []
        }
        
        // Gets the formatted and averaged results.
        let frameProbabilities = dataToFloatArray(framesOutputTensor.data) ?? []
        let onsetProbabilities = dataToFloatArray(onsetsOutputTensor.data) ?? []
        let offsetProbabilities = dataToFloatArray(offsetsOutputTensor.data) ?? []
        let velocityProbabilities = dataToFloatArray(velocitiesOutputTensor.data) ?? []
        
//        let startTime = CFAbsoluteTimeGetCurrent()
        
        var noteSequence: [Note]
        
        if (!viterbiDecoding) {
            noteSequence = pianorollToNoteSequence(_frames: frameProbabilities, _onsets: onsetProbabilities, _offsets: offsetProbabilities, _velocities: velocityProbabilities, predictVelocities: predictVelocities)
        } else {
            let pianoroll = SoundClassifier.probsToPianorollViterbi(_frames: MfArray(frameProbabilities).reshape([32, 88]), _onsets: MfArray(onsetProbabilities).reshape([32, 88]), alpha: viterbiThreshold)
            let pianorollLogicalAnd = MfArray(zip(pianoroll[1~<, Matft.all].flatten().toArray() as! [Bool], pianoroll[~<-1, Matft.all].flatten().toArray() as! [Bool]).map { $0 && !$1 }).reshape([31, 88])
            
            let onsets = Matft.concatenate([pianoroll[~<1, Matft.all], pianorollLogicalAnd], axis: 0)
            noteSequence = pianorollToNoteSequence(_frames: pianoroll.astype(.Float).flatten().toArray() as! [Float32], _onsets: onsets.astype(.Float).flatten().toArray() as! [Float32], _offsets: offsetProbabilities, _velocities: velocityProbabilities, predictVelocities: predictVelocities)
        }
        
        print(noteSequence)
//        let endTime = CFAbsoluteTimeGetCurrent()
//        let timeElapsed = endTime - startTime
//        print("Time elapsed for post-processing: \(Int(timeElapsed * 1000)) ms.")
        
        return noteSequence
    }
    
    // https://github.com/magenta/magenta/blob/52828dc160781f422e670d414406ffe91c30066b/magenta/models/onsets_frames_transcription/infer_util.py#L28
    class func probsToPianorollViterbi(_frames: MfArray, _onsets: MfArray, alpha: Double = 0.5) -> MfArray {
        print("Using Viterbi decoding")
        var frameProbabilities = _frames.deepcopy()
        var onsetProbabilities = _onsets.deepcopy()
        
        let n = onsetProbabilities.shape[0]
        let d = onsetProbabilities.shape[1]
        
        let lossMatrix = Matft.nums(0, shape: [n, d, 2])
        let pathMatrix = Matft.nums(0, shape: [n, d, 2])
        
        
//        print(frameProbabilities.shape)
        frameProbabilities = frameProbabilities.expand_dims(axis: 2)
//        print(frameProbabilities.shape)
        frameProbabilities = Matft.concatenate([1 - frameProbabilities, frameProbabilities], axis: 2)
//        print(frameProbabilities.shape)
        onsetProbabilities = onsetProbabilities.expand_dims(axis: 2)
        onsetProbabilities = Matft.concatenate([1 - onsetProbabilities, onsetProbabilities], axis: 2)
        
        let frameLosses = (1 - alpha) * -Matft.math.log(frameProbabilities)
        let onsetLosses = alpha * -Matft.math.log(onsetProbabilities)
        
        lossMatrix[0, Matft.all, Matft.all] = frameLosses[0, Matft.all, Matft.all] + onsetLosses[0, Matft.all, Matft.all]
        for i in [Int](1..<n) {
            let tileTarget = lossMatrix[i - 1, Matft.all, Matft.all].expand_dims(axis: 2) // New axis is null?
            let transitionLosses = Matft.concatenate([tileTarget, tileTarget], axis: 2)
            
            transitionLosses[Matft.all, 0, 0] += onsetLosses[i, Matft.all, 0]
            transitionLosses[Matft.all, 0, 1] += onsetLosses[i, Matft.all, 1]
            transitionLosses[Matft.all, 1, 0] += onsetLosses[i, Matft.all, 0]
            transitionLosses[Matft.all, 1, 1] += onsetLosses[i, Matft.all, 0]
            
            pathMatrix[i, Matft.all, Matft.all] = Matft.stats.argmin(transitionLosses, axis: 1)
            
            lossMatrix[i, Matft.all, 0] = transitionLosses[Matft.arange(start: 0, to: d, by: 1), pathMatrix[i, Matft.all, 0].astype(.Int), 0]
            lossMatrix[i, Matft.all, 1] = transitionLosses[Matft.arange(start: 0, to: d, by: 1), pathMatrix[i, Matft.all, 1].astype(.Int), 1]
            
            lossMatrix[i, Matft.all, Matft.all] += frameLosses[i, Matft.all, Matft.all]
        }
        
        let pianoroll = Matft.nums(0, shape: [n, d], mftype: .Float) // Should be bools?
        pianoroll[n - 1, Matft.all] = Matft.stats.argmin(lossMatrix[n - 1, Matft.all, Matft.all], axis: -1)
        for i in [Int](0...n - 2).reversed() {
            pianoroll[i, Matft.all] = pathMatrix[i + 1, Matft.arange(start: 0, to: d, by: 1), pianoroll[i + 1, Matft.all].astype(.Int)]
        }
        
        return pianoroll.astype(.Bool)
    }
    
    // https://github.com/magenta/note-seq/blob/55e4432a6686cec84b392c2290d4c2a1d040675c/note_seq/sequences_lib.py#L1950
    func pianorollToNoteSequence(_frames: [Float32], framesPerSecond: Int = 32, velocityScale: Int = 80, velocityBias: Int = 10, _onsets: [Float32], _offsets: [Float32], _velocities: [Float32], predictVelocities: Bool) -> [Note] {
        var sequence: [Note] = []
        let frameLengthSeconds = 1.0 / Double(framesPerSecond)
        
        var pitchStartStep: Dictionary<Int, Int> = [:]
        var onsetVelocities: [Int] = Array(repeating: 0, count: 128) // Maximum midi notes
        let velocities = MfArray(_velocities).reshape([32, 88])

        let frames = MfArray(_frames, mftype: .Float).reshape([32, 88])
//        print(frames.mftype)
        let framesPredicted = Matft.nums_like(0, mfarray: frames)
//        print(framesPredicted.mftype)
        framesPredicted[frames > 0.5] = MfArray([1])
        let framePredictionsPadded = Matft.append(framesPredicted, values: MfArray([Array(repeating: 0, count: 88)]), axis: 0)
//        print(framePredictionsPadded.mftype)
        
        let onsets = MfArray(_onsets, mftype: .Float).reshape([32, 88])
        let onsetsPredicted = Matft.nums_like(0, mfarray: onsets)
        onsetsPredicted[onsets > 0.5] = MfArray([1])
        let onsetPredictionsPadded = Matft.append(onsetsPredicted, values: MfArray([Array(repeating: 0, count: 88)]), axis: 0)
        
        let offsets = MfArray(_offsets).reshape([32, 88])
        let offsetsPredicted = Matft.nums_like(0, mfarray: offsets)
        offsetsPredicted[offsets > 0.0] = MfArray([1])
        let offsetPredictionsPadded = Matft.append(offsetsPredicted, values: MfArray([Array(repeating: 0, count: 88)]), axis: 0)
    
        /// Ensure that any frame with an onset prediction is considered active.
        let framesConfirmedByOnsets = Matft.nums_like(0, mfarray: framePredictionsPadded)
        let framesOnsetsSum = framePredictionsPadded + onsetPredictionsPadded
        framesConfirmedByOnsets[framesOnsetsSum > 0] = MfArray([1])
        
        // If the frame and offset are both on, then turn it off.
        framesConfirmedByOnsets[(framePredictionsPadded + offsetPredictionsPadded) > 1] = MfArray([0])
        
        func endPitch(pitch: Int, endFrameIndex: Int) {
            // End an active pitch
            guard let pitchStart = pitchStartStep[pitch] else {
                return
            }
            
            let startTime = Double(pitchStart) * frameLengthSeconds
            let endTime = Double(endFrameIndex) * frameLengthSeconds
            
            let note = Note(pitch: Int32(pitch), startTime: startTime, endTime: endTime, velocity: Int32(onsetVelocities[pitch]))
            sequence.append(note)
            
            pitchStartStep.removeValue(forKey: pitch)
        }
        
        func processActivePitch(pitch: Int, frameIndex: Int) {
            if (!pitchStartStep.keys.contains(pitch)) {
                if (onsetPredictionsPadded[frameIndex, pitch] as! Bool == true) {
                    pitchStartStep[pitch] = frameIndex
                    onsetVelocities[pitch] = predictVelocities ? unscaleVelocity(velocity: velocities[frameIndex, pitch] as! Float32, scale: velocityScale, bias: velocityBias) : 60
                }
            } else {
                // pitch is already active, but if this is a new onset, we should end the note and start a new one.
                if (onsetPredictionsPadded[frameIndex, pitch] as! Bool == true && onsetPredictionsPadded[frameIndex - 1, pitch] as! Bool == false) {
                    endPitch(pitch: pitch, endFrameIndex: frameIndex)
                    pitchStartStep[pitch] = frameIndex
                    onsetVelocities[pitch] = predictVelocities ? unscaleVelocity(velocity: velocities[frameIndex, pitch] as! Float32, scale: velocityScale, bias: velocityBias) : 60
                }
            }
        }
        
        for (i, f) in framesConfirmedByOnsets.toArray().enumerated() {
            let _frame: [Float] = f as! [Float]
            for (pitch, isActive) in _frame.enumerated() {
                if (isActive > 0) {
                    processActivePitch(pitch: pitch, frameIndex: i)
                } else {
                    endPitch(pitch: pitch, endFrameIndex: i)
                }
            }
        }
        
        return sequence
    }
    
    private func unscaleVelocity(velocity: Float32, scale: Int, bias: Int) -> Int {
        let unscaled = max(min(velocity, 1.0), 0.0) * Float32(scale) + Float32(bias)
        return Int(unscaled)
    }
    
    private func int16ArrayToData(_ buffer: [Int16]) -> Data {
        let floatData = buffer.map { Float($0) / Float(Int16.max) }
        return floatData.withUnsafeBufferPointer(Data.init)
    }
    
    private func dataToFloatArray(_ data: Data) -> [Float]? {
        guard data.count % MemoryLayout<Float>.stride == 0 else { return nil }
        
#if swift(>=5.0)
        return data.withUnsafeBytes { .init($0.bindMemory(to: Float.self)) }
#else
        return data.withUnsafeBytes {
            .init(UnsafeBufferPointer<Float>(
                start: $0,
                count: unsafeData.count / MemoryLayout<Element>.stride
            ))
        }
#endif // swift(>=5.0)
    }
}
