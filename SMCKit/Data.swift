//
//  Data.swift
//  SMCKit
//
//  Created by Dominik Louven on 03.04.17.
//  Copyright © 2017 beltex. All rights reserved.
//

import Foundation

//------------------------------------------------------------------------------
// MARK: Defined by AppleSMC.kext
//------------------------------------------------------------------------------

/// Defined by AppleSMC.kext
///
/// This is the predefined struct that must be passed to communicate with the
/// AppleSMC driver. While the driver is closed source, the definition of this
/// struct happened to appear in the Apple PowerManagement project at around
/// version 211, and soon after disappeared. It can be seen in the PrivateLib.c
/// file under pmconfigd. Given that it is C code, this is the closest
/// translation to Swift from a type perspective.
///
/// ### Issues
///
/// * Padding for struct alignment when passed over to C side
/// * Size of struct must be 80 bytes
/// * C array's are bridged as tuples
///
/// http://www.opensource.apple.com/source/PowerManagement/PowerManagement-211/
public struct SMCParamStruct{
    
    /// I/O Kit function selector
    public enum Selector: UInt8 {
        case kSMCHandleYPCEvent  = 2
        case kSMCReadKey         = 5
        case kSMCWriteKey        = 6
        case kSMCGetKeyFromIndex = 8
        case kSMCGetKeyInfo      = 9
    }
    
    /// Return codes for SMCParamStruct.result property
    public enum Result: UInt8 {
        case kSMCSuccess     = 0
        case kSMCError       = 1
        case kSMCKeyNotFound = 132
    }
    
    public struct SMCVersion{
        var major: CUnsignedChar = 0
        var minor: CUnsignedChar = 0
        var build: CUnsignedChar = 0
        var reserved: CUnsignedChar = 0
        var _release: CUnsignedShort = 0
    }
    
    public struct SMCPLimitData{
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }
    
    public struct SMCKeyInfoData {
        /// How many bytes written to SMCParamStruct.bytes
        var dataSize: IOByteCount = 0
        
        /// Type of data written to SMCParamStruct.bytes. This lets us know how
        /// to interpret it (translate it to human readable)
        var dataType: UInt32 = 0
        
        var dataAttributes: UInt8 = 0
    }
    
    /// FourCharCode telling the SMC what we want
    var key: UInt32 = 0
    
    var vers = SMCVersion()
    
    var pLimitData = SMCPLimitData()
    
    var keyInfo = SMCKeyInfoData()
    
    /// Padding for struct alignment when passed over to C side
    var padding: UInt16 = 0
    
    /// Result of an operation
    var result: UInt8 = 0
    
    var status: UInt8 = 0
    
    /// Method selector
    var data8: UInt8 = 0
    
    var data32: UInt32 = 0
    
    /// Data returned from the SMC
    var bytes = SMCBytes(UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                 UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                 UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                 UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                 UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                 UInt8(0), UInt8(0))
}
