//
// SMC.swift
// SMCKit
//
// The MIT License
//
// Copyright (C) 2014-2015  beltex <http://beltex.github.io>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import IOKit
import Foundation

//------------------------------------------------------------------------------
// MARK: Type Aliases
//------------------------------------------------------------------------------

// http://stackoverflow.com/a/22383661

/// Floating point, unsigned, 14 bits exponent, 2 bits fraction
public typealias FPE2 = (UInt8, UInt8)

/// Floating point, signed, 7 bits exponent, 8 bits fraction
public typealias SP78 = (UInt8, UInt8)

public typealias SMCBytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8)

//------------------------------------------------------------------------------
// MARK: Standard Library Extensions
//------------------------------------------------------------------------------

extension UInt32 {
    
    init(fromBytes bytes: (UInt8, UInt8, UInt8, UInt8)) {
        self = UInt32(bytes.0) << 24 |
            UInt32(bytes.1) << 16 |
            UInt32(bytes.2) << 8  |
            UInt32(bytes.3)
    }
}

extension Bool {
    
    init(fromByte byte: UInt8) {
        self = byte == 1 ? true : false
    }
}

public extension Int {
    
    init(fromFPE2 bytes: FPE2) {
        self = (Int(bytes.0) << 6) + (Int(bytes.1) >> 2)
    }
    
    func toFPE2() -> FPE2 {
        return (UInt8(self >> 6), UInt8((self << 2) ^ ((self >> 6) << 8)))
    }
}

extension Double {
    
    init(fromSP78 bytes: SP78) {
        // FIXME: Handle second byte
        let sign = bytes.0 & 0x80 == 0 ? 1.0 : -1.0
        self = sign * Double(bytes.0 & 0x7F)    // AND to mask sign bit
    }
}

// Thanks to Airspeed Velocity for the great idea!
// http://airspeedvelocity.net/2015/05/22/my-talk-at-swift-summit/
public extension FourCharCode {
    
    init(fromString str: String) {
        precondition(str.characters.count == 4)
        
        self = str.utf8.reduce(0) { sum, character in
            return sum << 8 | UInt32(character)
        }
    }
    
    init(fromStaticString str: StaticString) {
        precondition(str.utf8CodeUnitCount == 4)
        
        self = str.withUTF8Buffer { (buffer) -> UInt32 in
            // FIXME: Compiler hang, need to break up expression
            let temp = UInt32(buffer[0]) << 24
            return temp                    |
                UInt32(buffer[1]) << 16 |
                UInt32(buffer[2]) << 8  |
                UInt32(buffer[3])
        }
    }
    
    func toString() -> String {
        return String(describing: UnicodeScalar(self >> 24 & 0xff)!) +
            String(describing: UnicodeScalar(self >> 16 & 0xff)!) +
            String(describing: UnicodeScalar(self >> 8  & 0xff)!) +
            String(describing: UnicodeScalar(self       & 0xff)!)
    }
}


//------------------------------------------------------------------------------
// MARK: SMC Client
//------------------------------------------------------------------------------

/// I/O Kit common error codes - as defined in <IOKit/IOReturn.h>
///
/// Swift currently can't import complex macros, thus we have to manually add
/// them here.

/// Privilege violation
private let kIOReturnNotPrivileged = iokit_common_err(0x2c1)

/// Based on macro of the same name in <IOKit/IOReturn.h>. Generates the full
/// 32-bit error code.
///
/// - parameter code: The specific I/O Kit error code. Last 14 bits
private func iokit_common_err(_ code: Int32) -> kern_return_t {
    // I/O Kit system code is 0x38. First 6 bits of error code. Passed to
    // err_system() macro as defined in <mach/error.h>
    let SYS_IOKIT: Int32 = (0x38 & 0x3f) << 26
    
    // I/O Kit subsystem code is 0. Middle 12 bits of error code. Passed to
    // err_sub() macro as defined in <mach/error.h>
    let SUB_IOKIT_COMMON: Int32 = (0 & 0xfff) << 14
    
    return SYS_IOKIT | SUB_IOKIT_COMMON | code
}

/// SMC data type information
public struct DataTypes {
    
    /// Fan information struct
    public static let FDS =
        DataType(type: FourCharCode(fromStaticString: "{fds"), size: 16)
    public static let Flag =
        DataType(type: FourCharCode(fromStaticString: "flag"), size: 1)
    /// See type aliases
    public static let FPE2 =
        DataType(type: FourCharCode(fromStaticString: "fpe2"), size: 2)
    /// See type aliases
    public static let SP78 =
        DataType(type: FourCharCode(fromStaticString: "sp78"), size: 2)
    public static let UInt8 =
        DataType(type: FourCharCode(fromStaticString: "ui8 "), size: 1)
    public static let UInt32 =
        DataType(type: FourCharCode(fromStaticString: "ui32"), size: 4)
}

public struct SMCKey {
    let code: FourCharCode
    let info: DataType
}

public struct DataType: Equatable{
    let type: FourCharCode
    let size: UInt32
}

public func ==(lhs: DataType, rhs: DataType) -> Bool {
    return lhs.type == rhs.type && lhs.size == rhs.size
}

//------------------------------------------------------------------------------
// MARK: Temperature
//------------------------------------------------------------------------------

/// The list is NOT exhaustive. In addition, the names of the sensors may not be
/// mapped to the correct hardware component.
///
/// ### Sources
///
/// * powermetrics(1)
/// * https://www.apple.com/downloads/dashboard/status/istatpro.html
/// * https://github.com/hholtmann/smcFanControl
/// * https://github.com/jedda/OSX-Monitoring-Tools
/// * http://www.opensource.apple.com/source/net_snmp/
/// * http://www.parhelia.ch/blog/statics/k3_keys.html
@objc
public class TemperatureSensors : NSObject{
    
    public static let AMBIENT_AIR_0 = TemperatureSensor(name: "AMBIENT_AIR_0",
                                                        code: FourCharCode(fromStaticString: "TA0P"))
    public static let AMBIENT_AIR_1 = TemperatureSensor(name: "AMBIENT_AIR_1",
                                                        code: FourCharCode(fromStaticString: "TA1P"))
    // Via powermetrics(1)
    public static let CPU_0_DIE = TemperatureSensor(name: "CPU_0_DIE",
                                                    code: FourCharCode(fromStaticString: "TC0F"))
    public static let CPU_0_DIODE = TemperatureSensor(name: "CPU_0_DIODE",
                                                      code: FourCharCode(fromStaticString: "TC0D"))
    public static let CPU_0_HEATSINK = TemperatureSensor(name: "CPU_0_HEATSINK",
                                                         code: FourCharCode(fromStaticString: "TC0H"))
    public static let CPU_0_PROXIMITY =
        TemperatureSensor(name: "CPU_0_PROXIMITY",
                          code: FourCharCode(fromStaticString: "TC0P"))
    public static let ENCLOSURE_BASE_0 =
        TemperatureSensor(name: "ENCLOSURE_BASE_0",
                          code: FourCharCode(fromStaticString: "TB0T"))
    public static let ENCLOSURE_BASE_1 =
        TemperatureSensor(name: "ENCLOSURE_BASE_1",
                          code: FourCharCode(fromStaticString: "TB1T"))
    public static let ENCLOSURE_BASE_2 =
        TemperatureSensor(name: "ENCLOSURE_BASE_2",
                          code: FourCharCode(fromStaticString: "TB2T"))
    public static let ENCLOSURE_BASE_3 =
        TemperatureSensor(name: "ENCLOSURE_BASE_3",
                          code: FourCharCode(fromStaticString: "TB3T"))
    public static let GPU_0_DIODE = TemperatureSensor(name: "GPU_0_DIODE",
                                                      code: FourCharCode(fromStaticString: "TG0D"))
    public static let GPU_0_HEATSINK = TemperatureSensor(name: "GPU_0_HEATSINK",
                                                         code: FourCharCode(fromStaticString: "TG0H"))
    public static let GPU_0_PROXIMITY =
        TemperatureSensor(name: "GPU_0_PROXIMITY",
                          code: FourCharCode(fromStaticString: "TG0P"))
    public static let HDD_PROXIMITY = TemperatureSensor(name: "HDD_PROXIMITY",
                                                        code: FourCharCode(fromStaticString: "TH0P"))
    public static let HEATSINK_0 = TemperatureSensor(name: "HEATSINK_0",
                                                     code: FourCharCode(fromStaticString: "Th0H"))
    public static let HEATSINK_1 = TemperatureSensor(name: "HEATSINK_1",
                                                     code: FourCharCode(fromStaticString: "Th1H"))
    public static let HEATSINK_2 = TemperatureSensor(name: "HEATSINK_2",
                                                     code: FourCharCode(fromStaticString: "Th2H"))
    public static let LCD_PROXIMITY = TemperatureSensor(name: "LCD_PROXIMITY",
                                                        code: FourCharCode(fromStaticString: "TL0P"))
    public static let MEM_SLOT_0 = TemperatureSensor(name: "MEM_SLOT_0",
                                                     code: FourCharCode(fromStaticString: "TM0S"))
    public static let MEM_SLOTS_PROXIMITY =
        TemperatureSensor(name: "MEM_SLOTS_PROXIMITY",
                          code: FourCharCode(fromStaticString: "TM0P"))
    public static let MISC_PROXIMITY = TemperatureSensor(name: "MISC_PROXIMITY",
                                                         code: FourCharCode(fromStaticString: "Tm0P"))
    public static let NORTHBRIDGE = TemperatureSensor(name: "NORTHBRIDGE",
                                                      code: FourCharCode(fromStaticString: "TN0H"))
    public static let NORTHBRIDGE_DIODE =
        TemperatureSensor(name: "NORTHBRIDGE_DIODE",
                          code: FourCharCode(fromStaticString: "TN0D"))
    public static let NORTHBRIDGE_PROXIMITY =
        TemperatureSensor(name: "NORTHBRIDGE_PROXIMITY",
                          code: FourCharCode(fromStaticString: "TN0P"))
    public static let ODD_PROXIMITY = TemperatureSensor(name: "ODD_PROXIMITY",
                                                        code: FourCharCode(fromStaticString: "TO0P"))
    public static let PALM_REST = TemperatureSensor(name: "PALM_REST",
                                                    code: FourCharCode(fromStaticString: "Ts0P"))
    public static let PWR_SUPPLY_PROXIMITY =
        TemperatureSensor(name: "PWR_SUPPLY_PROXIMITY",
                          code: FourCharCode(fromStaticString: "Tp0P"))
    public static let THUNDERBOLT_0 = TemperatureSensor(name: "THUNDERBOLT_0",
                                                        code: FourCharCode(fromStaticString: "TI0P"))
    public static let THUNDERBOLT_1 = TemperatureSensor(name: "THUNDERBOLT_1",
                                                        code: FourCharCode(fromStaticString: "TI1P"))
    
    public static let all = [AMBIENT_AIR_0.code : AMBIENT_AIR_0,
                             AMBIENT_AIR_1.code : AMBIENT_AIR_1,
                             CPU_0_DIE.code : CPU_0_DIE,
                             CPU_0_DIODE.code : CPU_0_DIODE,
                             CPU_0_HEATSINK.code : CPU_0_HEATSINK,
                             CPU_0_PROXIMITY.code : CPU_0_PROXIMITY,
                             ENCLOSURE_BASE_0.code : ENCLOSURE_BASE_0,
                             ENCLOSURE_BASE_1.code : ENCLOSURE_BASE_1,
                             ENCLOSURE_BASE_2.code : ENCLOSURE_BASE_2,
                             ENCLOSURE_BASE_3.code : ENCLOSURE_BASE_3,
                             GPU_0_DIODE.code : GPU_0_DIODE,
                             GPU_0_HEATSINK.code : GPU_0_HEATSINK,
                             GPU_0_PROXIMITY.code : GPU_0_PROXIMITY,
                             HDD_PROXIMITY.code : HDD_PROXIMITY,
                             HEATSINK_0.code : HEATSINK_0,
                             HEATSINK_1.code : HEATSINK_1,
                             HEATSINK_2.code : HEATSINK_2,
                             MEM_SLOT_0.code : MEM_SLOT_0,
                             MEM_SLOTS_PROXIMITY.code: MEM_SLOTS_PROXIMITY,
                             PALM_REST.code : PALM_REST,
                             LCD_PROXIMITY.code : LCD_PROXIMITY,
                             MISC_PROXIMITY.code : MISC_PROXIMITY,
                             NORTHBRIDGE.code : NORTHBRIDGE,
                             NORTHBRIDGE_DIODE.code : NORTHBRIDGE_DIODE,
                             NORTHBRIDGE_PROXIMITY.code : NORTHBRIDGE_PROXIMITY,
                             ODD_PROXIMITY.code : ODD_PROXIMITY,
                             PWR_SUPPLY_PROXIMITY.code : PWR_SUPPLY_PROXIMITY,
                             THUNDERBOLT_0.code : THUNDERBOLT_0,
                             THUNDERBOLT_1.code : THUNDERBOLT_1]
}

@objc
public class TemperatureSensor : NSObject{
    public let name: String
    public let code: FourCharCode
    
    init(name: String, code: FourCharCode){
        self.name = name
        self.code = code
    }
}

public enum TemperatureUnit {
    case celius
    case fahrenheit
    case kelvin
    
    public static func toFahrenheit(_ celius: Double) -> Double {
        // https://en.wikipedia.org/wiki/Fahrenheit#Definition_and_conversions
        return (celius * 1.8) + 32
    }
    
    public static func toKelvin(_ celius: Double) -> Double {
        // https://en.wikipedia.org/wiki/Kelvin
        return celius + 273.15
    }
}

//------------------------------------------------------------------------------
// MARK: Fan
//------------------------------------------------------------------------------
@objc
public class Fan : NSObject{
    // TODO: Should we start the fan id from 1 instead of 0?
    public var id: Int
    public var name: String
    public var minSpeed: Int
    public var maxSpeed: Int
    
    init(id: Int, name: String, minSpeed: Int, maxSpeed: Int){
        self.name = name
        self.id = id
        self.minSpeed = minSpeed
        self.maxSpeed = maxSpeed
    }
}

//------------------------------------------------------------------------------
// MARK: Miscellaneous
//------------------------------------------------------------------------------
@objc
public class batteryInfo : NSObject{
    public var batteryCount: Int = -1
    public var isACPresent: Bool = false
    public var isBatteryPowered: Bool = false
    public var isBatteryOk: Bool = false
    public var isCharging: Bool = false
    
    init(batteryCount: Int, isACPresent: Bool, isBatteryPowered: Bool, isBatteryOk: Bool, isCharging: Bool){
        self.batteryCount = batteryCount
        self.isBatteryPowered = isBatteryPowered
        self.isBatteryOk = isBatteryOk
        self.isCharging = isCharging
    }
}
