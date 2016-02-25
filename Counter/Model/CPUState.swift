//
//  CPUState.swift
//  Counter
//
//  Created by Brian Hill github.com/brianhill on 2/12/16.
//

// CPUState defines the various CPU registers we need to simulate an HP-35.
//
// This reference is the most thorough, but at the moment a bunch of the image links are broken:
//
// http://home.citycable.ch/pierrefleur/Jacques-Laporte/A&R.htm
//
// This reference is sufficient:
//
// http://www.hpmuseum.org/techcpu.htm

import Foundation

typealias Nibble = UInt8 // This should be UInt4, but the smallest width unsigned integer Swift has is UInt8.

typealias Pointer = UInt8 // Also should be UInt4. In any case, we are not currently using this or Status.

typealias Status = UInt16 // Should be a UInt12 if we wanted exactly as many status bits as the HP-35.

// This is how many nibbles there are in a register:
let RegisterLength = 14

// This is how many of the nibbles are devoted to the exponent:
let ExponentLength = 3

// Two utilities for testing and display:
func nibbleFromCharacter(char: Character) -> Nibble {
    return Nibble(Int(String(char))!)
}

func hexCharacterFromNibble(nibble: Nibble) -> Character {
    return Character(String(format:"%1X", nibble))
}

// A register is 14 nibbles (56 bits). Mostly nibbles are used to represent the digits 0-9, but the leftmost one, nibble 13, corresponds to the sign of the mantissa, nibbles 12 to 3 inclusive represent 10 digits of mantissa, and nibbles 2 to 0 represent the exponent.
struct Register {
    var nibbles: [Nibble] = [Nibble](count:RegisterLength, repeatedValue: UInt8(0))
    
    // Hmmm. It seems I need the empty initializer because I created init(fromDecimalString:).
    init() {}
    
    // Initialize a register from a fourteen-digit decimal string (e.g., "91250000000902")
    init(fromDecimalString: String) {
        let characters = Array(fromDecimalString.characters)
        assert(RegisterLength == characters.count)
        var characterIdx = 0
        var nibbleIdx = RegisterLength - 1
        while nibbleIdx >= 0 {
            let char: Character = characters[characterIdx]
            nibbles[nibbleIdx] = nibbleFromCharacter(char)
            characterIdx += 1
            nibbleIdx -= 1
        }
    }
    
    func asDecimalString() -> String {
        var digits: String = ""
        var nibbleIdx = RegisterLength - 1
        while nibbleIdx >= 0 {
            let nibble = nibbles[nibbleIdx]
            let hexChar = hexCharacterFromNibble(nibble)
            digits.append(hexChar)
            nibbleIdx -= 1
        }
        return digits 
    }
    
    mutating func setNibble(index: Int, value: Nibble) {
        nibbles[index] = value
    }
}

class CPUState {
    
    // The singleton starts in the traditional state that an HP-35 is in when you power it on.
    // The display just shows 0 and a decimal point.
    static let sharedInstance = CPUState(decimalStringA: "00000000000000", decimalStringB: "02999999999999")
    
    var registers = [Register](count:7, repeatedValue:Register())
    
    // All the important initialization is done above when registers is assigned.
    init() {}
    
    // A method provided prinicipally for testing. Allows the state of the registers that record user input to be
    // initialized from decimal strings. Register C will be canonicalized from registers A and B. The remaining
    // registers will be initialized to zeros.
    init(decimalStringA: String, decimalStringB: String) {
        let registerA = Register(fromDecimalString: decimalStringA)
        let registerB = Register(fromDecimalString: decimalStringB)
        
        registers[RegId.A.rawValue] = registerA
        registers[RegId.B.rawValue] = registerB
        
        canonicalize()
    }
    
    // Computes and stores into register C whatever is currently showing to the user in A and B. Note that it
    // is possible for canonicalization to fail. For example 123.4567890 99 overflows when canonicalized. When it
    // fails due to overflow (or underflow), registers A and B are overwritten with overflow (or underflow) values.
    //
    // This function is unimplemented. I hard-coded in a value that will make the first of the five test cases pass.
    //
    // When you are done re-implementing this method, all five test cases should pass (and any other test cases
    // that obey the rules described in comments at the top of DisplayDecoder.swift should also pass).
    //
    // Make use of the enums RegisterASpecialValues and RegisterBSpecialValues so that you don't have to hard
    // code "2" to mean a decimal point (similarly for the other special values).
    func canonicalize() {
        let registerA = registers[RegId.A.rawValue]
        let registerB = registers[RegId.B.rawValue]
        var registerC = Register()
        var tempRegister = DisplayDecoder().getDisplayableCharacters(registerA, registerB: registerB);
        var idxC = 13
        var isNegative:Bool = false
        var exponentIsNegative:Bool = false
        
        //Check if A is positive or negative; set first nibble on Register C accordingly.
        if registerA.nibbles[13] == RegisterASpecialValues.Minus.rawValue {
            registerC.setNibble(idxC, value: RegisterASpecialValues.Minus.rawValue)
            isNegative = true
        }
        else{
            registerC.setNibble(idxC, value: 0)
        }
        idxC--;
        
        
        
        //Strip leading zeroes and copy main number from Register A to Register C
        var leadingZerosGone:Bool = false
        var middleCounter:Int = 12
        while middleCounter > 2 {
            
            if registerA.nibbles[middleCounter] != 0 && !leadingZerosGone {
                leadingZerosGone = true
            }
            
            if(leadingZerosGone){
                registerC.setNibble(idxC, value: registerA.nibbles[middleCounter])
                idxC--;
            }
            
            middleCounter--
            
        }
        
        //Fill in any missing spaces with zeroes
        while idxC > 2{
            registerC.setNibble(idxC, value: 0)
            idxC--
        }
        
        //At this point we have a correct representation of registers 13 to 3
        
        let exponentOfAIsNegative = (registerA.nibbles[2] == RegisterASpecialValues.Minus.rawValue ? -1 : 1)
        var exponentFromA = Int(nibbleFromCharacter(tempRegister[13].rawValue)*10)
        exponentFromA += Int(nibbleFromCharacter(tempRegister[14].rawValue))
        exponentFromA *= exponentOfAIsNegative
        
        var rawNumber:String = ""
        for m in 1...11 {
            rawNumber.append(tempRegister[m].rawValue)
        }
        let legitNumber = (rawNumber as NSString).floatValue
        let displayExponent = Int(log10(legitNumber))
        var finalExponent = exponentFromA + displayExponent
        
        if finalExponent > 99 { overflow(!isNegative) }
        else if finalExponent < -99 { underflow() }
        
        if(finalExponent<0){
            exponentIsNegative = true
            finalExponent += 100
        }
        
        //At this point, we have the main number, whether it is positive or negative, the exponent, in its proper form, and whether it is positive or negative.
        
        registerC.setNibble(2, value: (exponentIsNegative ? RegisterASpecialValues.Minus.rawValue : 0 ) )
        registerC.setNibble(1, value: Nibble(finalExponent/10))
        registerC.setNibble(0, value: Nibble(finalExponent%10))
        
        registers[RegId.C.rawValue] = registerC
    }
    
    // Displays positive or negative overflow value
    func overflow(positive: Bool) {
        registers[RegId.A.rawValue] = Register(fromDecimalString: positive ? "09999999999099" : "99999999999099")
        registers[RegId.B.rawValue] = Register(fromDecimalString: "02000000000000")
        canonicalize()
    }
    
    // Displays underflow value
    func underflow() {
        registers[RegId.A.rawValue] = Register(fromDecimalString: "00000000000000")
        registers[RegId.B.rawValue] = Register(fromDecimalString: "02999999999999")
        canonicalize()
    }
    
    func decimalStringForRegister(regId: RegId) -> String {
        let register = registers[regId.rawValue]
        return register.asDecimalString()
    }
    
}

enum RegId: Int {
    case A = 0 // General Purpose (math or scratchpad)
    case B = 1 // General Purpose (math or scratchpad)
    case C = 2 // X Register
    case D = 3 // Y Register
    case E = 4 // Z Register
    case F = 5 // T (top or trigonemtric) Register
    case M = 6 // Scratchpad (like A and B, but no math)
}
