//
//  LineEndingScannerTests.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2022-04-08.
//
//  ---------------------------------------------------------------------------
//
//  © 2022 1024jp
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import XCTest
@testable import CotEditor

final class LineEndingScannerTests: XCTestCase {
    
    func testScanner() {
        
        let storage = NSTextStorage(string: "dog\ncat\r\ncow")
        let scanner = LineEndingScanner(textStorage: storage, lineEnding: .lf)
        
        storage.replaceCharacters(in: NSRange(0..<3), with: "dog\u{85}cow")
        // test outline parsing with publisher
        let expectation = self.expectation(description: "didScanLineEndings")
        
        let observer = scanner.$inconsistentLineEndings
            .sink { (lineEndings) in
                XCTAssertEqual(lineEndings, [LineEndingLocation(lineEnding: .nel, location: 3),
                                             LineEndingLocation(lineEnding: .crlf, location: 11)])
                expectation.fulfill()
            }
        self.wait(for: [expectation], timeout: .zero)
        
        observer.cancel()
    }
    
}