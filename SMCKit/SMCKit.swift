//
//  SMCKit.swift
//  SMCKit
//
//  Created by Dominik Louven on 31.03.17.
//  Copyright © 2017 beltex. All rights reserved.
//

import Foundation

/// Apple System Management Controller (SMC) user-space client for Intel-based
/// Macs. Works by talking to the AppleSMC.kext (kernel extension), the closed
/// source driver for the SMC.

//dlouven -> convert this to class for use in objective c
@objc
public class SMCKit : NSObject{
    
    public enum SMCError: Int {
        
        /// AppleSMC driver not found
        case driverNotFound
        
        /// Failed to open a connection to the AppleSMC driver
        case failedToOpen
        
        /// This SMC key is not valid on this machine
        case keyNotFound
        
        /// Requires root privileges
        case notPrivileged
        
        /// Fan speed must be > 0 && <= fanMaxSpeed
        case unsafeFanSpeed
        
        /// https://developer.apple.com/library/mac/qa/qa1075/_index.html
        ///
        /// - parameter kIOReturn: I/O Kit error code
        /// - parameter SMCResult: SMC specific return code
        case unknown
    }
    
    /// Connection to the SMC driver
    fileprivate static var connection: io_connect_t = 0
    
    /// Open connection to the SMC driver. This must be done first before any
    /// other calls
    public func open() {
        let service = IOServiceGetMatchingService(kIOMasterPortDefault,
                                                  IOServiceMatching("AppleSMC"))
        
        //if service == 0 //{ return SMCError.driverNotFound }
        
        let result = IOServiceOpen(service, mach_task_self_, 0,
                                   &SMCKit.connection)
        IOObjectRelease(service)
        
        //if result != kIOReturnSuccess { throw SMCError.failedToOpen }
    }
    
    /// Close connection to the SMC driver
    public func close() -> Bool {
        let result = IOServiceClose(SMCKit.connection)
        return result == kIOReturnSuccess ? true : false
    }
    
    /// Get information about a key
    public func keyInformation(_ key: FourCharCode) throws -> DataType {
        var inputStruct = SMCParamStruct()
        
        inputStruct.key = key
        inputStruct.data8 = SMCParamStruct.Selector.kSMCGetKeyInfo.rawValue
        
        let outputStruct = try callDriver(&inputStruct)
        
        return DataType(type: outputStruct.keyInfo.dataType,
                        size: outputStruct.keyInfo.dataSize)
    }
    
    /// Get information about the key at index
    public func keyInformationAtIndex(_ index: Int) throws ->
        FourCharCode {
            var inputStruct = SMCParamStruct()
            
            inputStruct.data8 = SMCParamStruct.Selector.kSMCGetKeyFromIndex.rawValue
            inputStruct.data32 = UInt32(index)
            
            let outputStruct = try callDriver(&inputStruct)
            
            return outputStruct.key
    }
    
    /// Read data of a key
    public func readData(_ key: SMCKey) throws -> SMCBytes {
        var inputStruct = SMCParamStruct()
        
        inputStruct.key = key.code
        inputStruct.keyInfo.dataSize = UInt32(key.info.size)
        inputStruct.data8 = SMCParamStruct.Selector.kSMCReadKey.rawValue
        
        let outputStruct = try callDriver(&inputStruct)
        
        return outputStruct.bytes
    }
    
    /// Write data for a key
    public func writeData(_ key: SMCKey, data: SMCBytes) throws {
        var inputStruct = SMCParamStruct()
        
        inputStruct.key = key.code
        inputStruct.bytes = data
        inputStruct.keyInfo.dataSize = UInt32(key.info.size)
        inputStruct.data8 = SMCParamStruct.Selector.kSMCWriteKey.rawValue
        
        try callDriver(&inputStruct)
    }
    
    /// Make an actual call to the SMC driver
    public func callDriver(_ inputStruct: inout SMCParamStruct,
                                  selector: SMCParamStruct.Selector = .kSMCHandleYPCEvent)
        throws -> SMCParamStruct {
            assert(MemoryLayout<SMCParamStruct>.stride == 80, "SMCParamStruct size is != 80")
            
            var outputStruct = SMCParamStruct()
            let inputStructSize = MemoryLayout<SMCParamStruct>.stride
            var outputStructSize = MemoryLayout<SMCParamStruct>.stride
            
            let result = IOConnectCallStructMethod(SMCKit.connection,
                                                   UInt32(selector.rawValue),
                                                   &inputStruct,
                                                   inputStructSize,
                                                   &outputStruct,
                                                   &outputStructSize)
            
            switch (result, outputStruct.result) {
            case (kIOReturnSuccess, SMCParamStruct.Result.kSMCSuccess.rawValue):
                return outputStruct
           // case (kIOReturnSuccess, SMCParamStruct.Result.kSMCKeyNotFound.rawValue):
                //throw SMCError.keyNotFound(code: inputStruct.key.toString())
            //case (kIOReturnNotPrivileged, _):
                //throw SMCError.notPrivileged
            default:
                return outputStruct;
                //throw SMCError.unknown(kIOReturn: result,
                 //                      SMCResult: outputStruct.result)
            }
    }
    
    /// Get all valid SMC keys for this machine
    public func allKeys() throws -> [SMCKey] {
        let count = try keyCount()
        var keys = [SMCKey]()
        
        for i in 0 ..< count {
            let key = try keyInformationAtIndex(i)
            let info = try keyInformation(key)
            keys.append(SMCKey(code: key, info: info))
        }
        
        return keys
    }
    
    /// Get the number of valid SMC keys for this machine
    public func keyCount() throws -> Int {
        let key = SMCKey(code: FourCharCode(fromStaticString: "#KEY"),
                         info: DataTypes.UInt32)
        
        let data = try readData(key)
        return Int(UInt32(fromBytes: (data.0, data.1, data.2, data.3)))
    }
    
    /// Is this key valid on this machine?
    public func isKeyFound(_ code: FourCharCode) throws -> Bool {
        do {
            try keyInformation(code)
        } catch SMCError.keyNotFound { return false }
        
        return true
    }
    
    public func allKnownTemperatureSensors() throws ->
        [TemperatureSensor] {
            var sensors = [TemperatureSensor]()
            
            for sensor in TemperatureSensors.all.values {
                if try isKeyFound(sensor.code) { sensors.append(sensor) }
            }
            
            return sensors
    }
    
    public func allUnknownTemperatureSensors() throws -> [TemperatureSensor] {
        let keys = try allKeys()
        
        return keys.filter { $0.code.toString().hasPrefix("T") &&
            $0.info == DataTypes.SP78 &&
            TemperatureSensors.all[$0.code] == nil }
            .map { TemperatureSensor(name: "Unknown", code: $0.code) }
    }
    
    /// Get current temperature of a sensor
    public func temperature(_ sensorCode: FourCharCode,
                                   unit: TemperatureUnit = .celius) throws -> Double {
        let data = try readData(SMCKey(code: sensorCode, info: DataTypes.SP78))
        
        let temperatureInCelius = Double(fromSP78: (data.0, data.1))
        
        switch unit {
        case .celius:
            return temperatureInCelius
        case .fahrenheit:
            return TemperatureUnit.toFahrenheit(temperatureInCelius)
        case .kelvin:
            return TemperatureUnit.toKelvin(temperatureInCelius)
        }
    }
    
    public func allFans() throws -> [Fan] {
        let count = try fanCount()
        var fans = [Fan]()
        
        for i in 0 ..< count {
            fans.append(try fan(i))
        }
        
        return fans
    }
    
    public func fan(_ id: Int) throws -> Fan {
        let name = try fanName(id)
        let minSpeed = try fanMinSpeed(id)
        let maxSpeed = try fanMaxSpeed(id)
        return Fan(id: id, name: name, minSpeed: minSpeed, maxSpeed: maxSpeed)
    }
    
    /// Number of fans this machine has. All Intel based Macs, except for the
    /// 2015 MacBook (8,1), have at least 1
    public func fanCount() throws -> Int {
        let key = SMCKey(code: FourCharCode(fromStaticString: "FNum"),
                         info: DataTypes.UInt8)
        
        let data = try readData(key)
        return Int(data.0)
    }
    
    public func fanName(_ id: Int) throws -> String {
        let key = SMCKey(code: FourCharCode(fromString: "F\(id)ID"),
                         info: DataTypes.FDS)
        let data = try readData(key)
        
        // The last 12 bytes of '{fds' data type, a custom struct defined by the
        // AppleSMC.kext that is 16 bytes, contains the fan name
        let c1  = String(UnicodeScalar(data.4))
        let c2  = String(UnicodeScalar(data.5))
        let c3  = String(UnicodeScalar(data.6))
        let c4  = String(UnicodeScalar(data.7))
        let c5  = String(UnicodeScalar(data.8))
        let c6  = String(UnicodeScalar(data.9))
        let c7  = String(UnicodeScalar(data.10))
        let c8  = String(UnicodeScalar(data.11))
        let c9  = String(UnicodeScalar(data.12))
        let c10 = String(UnicodeScalar(data.13))
        let c11 = String(UnicodeScalar(data.14))
        let c12 = String(UnicodeScalar(data.15))
        
        let name = c1 + c2 + c3 + c4 + c5 + c6 + c7 + c8 + c9 + c10 + c11 + c12
        
        let characterSet = CharacterSet.whitespaces
        return name.trimmingCharacters(in: characterSet)
    }
    
    public func fanCurrentSpeed(_ id: Int) throws -> Int {
        let key = SMCKey(code: FourCharCode(fromString: "F\(id)Ac"),
                         info: DataTypes.FPE2)
        
        let data = try readData(key)
        return Int(fromFPE2: (data.0, data.1))
    }
    
    public func fanMinSpeed(_ id: Int) throws -> Int {
        let key = SMCKey(code: FourCharCode(fromString: "F\(id)Mn"),
                         info: DataTypes.FPE2)
        
        let data = try readData(key)
        return Int(fromFPE2: (data.0, data.1))
    }
    
    public func fanMaxSpeed(_ id: Int) throws -> Int {
        let key = SMCKey(code: FourCharCode(fromString: "F\(id)Mx"),
                         info: DataTypes.FPE2)
        
        let data = try readData(key)
        return Int(fromFPE2: (data.0, data.1))
    }
    
    /// Requires root privileges. By minimum we mean that OS X can interject and
    /// raise the fan speed if needed, however it will not go below this.
    ///
    /// WARNING: You are playing with hardware here, BE CAREFUL.
    ///
    /// - Throws: Of note, `SMCKit.SMCError`'s `UnsafeFanSpeed` and `NotPrivileged`
    public func fanSetMinSpeed(_ id: Int, speed: Int) throws {
        _ = try fanMaxSpeed(id)
        //if speed <= 0 || speed > maxSpeed { throw SMCError.unsafeFanSpeed }
        
        let data = speed.toFPE2()
        let bytes = (data.0, data.1, UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                     UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                     UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                     UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                     UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                     UInt8(0), UInt8(0))
        
        let key = SMCKey(code: FourCharCode(fromString: "F\(id)Mn"),
                         info: DataTypes.FPE2)
        
        try writeData(key, data: bytes)
    }

    public func isOpticalDiskDriveFull() throws -> Bool {
        // TODO: Should we catch key not found? That just means the machine
        // doesn't have an ODD. Returning false though is not fully correct.
        // Maybe we could throw a no ODD error instead?
        let key = SMCKey(code: FourCharCode(fromStaticString: "MSDI"),
                         info: DataTypes.Flag)
        
        let data = try readData(key)
        return Bool(fromByte: data.0)
    }
    
    public func batteryInformation() throws -> batteryInfo {
        let batteryCountKey =
            SMCKey(code: FourCharCode(fromStaticString: "BNum"),
                   info: DataTypes.UInt8)
        let batteryPoweredKey =
            SMCKey(code: FourCharCode(fromStaticString: "BATP"),
                   info: DataTypes.Flag)
        let batteryInfoKey =
            SMCKey(code: FourCharCode(fromStaticString: "BSIn"),
                   info: DataTypes.UInt8)
        
        let batteryCountData = try readData(batteryCountKey)
        let batteryCount = Int(batteryCountData.0)
        
        let isBatteryPoweredData = try readData(batteryPoweredKey)
        let isBatteryPowered = Bool(fromByte: isBatteryPoweredData.0)
        
        let batteryInfoData = try readData(batteryInfoKey)
        let isCharging = batteryInfoData.0 & 1 == 1 ? true : false
        let isACPresent = (batteryInfoData.0 >> 1) & 1 == 1 ? true : false
        let isBatteryOk = (batteryInfoData.0 >> 6) & 1 == 1 ? true : false
        
        return batteryInfo(batteryCount: batteryCount, isACPresent: isACPresent,
                           isBatteryPowered: isBatteryPowered,
                           isBatteryOk: isBatteryOk,
                           isCharging: isCharging)
    }
}

