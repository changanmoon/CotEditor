//
//  HighlightParser.swift
//  Syntax
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2016-01-06.
//
//  ---------------------------------------------------------------------------
//
//  © 2004-2007 nakamuxu
//  © 2014-2024 1024jp
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

import Foundation
import StringBasics
import ValueRange


public enum NestableToken: Equatable, Hashable, Sendable {
    
    case inline(String)
    case pair(Pair<String>)
}


private struct NestableItem {
    
    var type: SyntaxType
    var token: NestableToken
    var role: Role
    var range: NSRange
    
    
    struct Role: OptionSet {
        
        let rawValue: Int
        
        static let begin = Self(rawValue: 1 << 0)
        static let end   = Self(rawValue: 1 << 1)
    }
}



// MARK: -

public struct HighlightParser: Sendable {
    
    // MARK: Internal Properties
    
    let extractors: [SyntaxType: [any HighlightExtractable]]
    let nestables: [NestableToken: SyntaxType]
    
    
    
    // MARK: Public Methods
    
    public var isEmpty: Bool {
        
        self.extractors.isEmpty && self.nestables.isEmpty
    }
    
    
    /// Extracts all highlight ranges in the parse range.
    ///
    /// - Parameters:
    ///   - string: The string to parse.
    ///   - range: The range where to parse.
    /// - Returns: A dictionary of ranges to highlight per syntax types.
    /// - Throws: CancellationError.
    public func parse(string: String, range: NSRange) async throws -> [Highlight] {
        
        try await withThrowingTaskGroup(of: [SyntaxType: [NSRange]].self) { group in
            for (type, extractors) in self.extractors {
                for extractor in extractors {
                    group.addTask { [type: try extractor.ranges(in: string, range: range)] }
                }
            }
            group.addTask { try self.extractNestables(string: string, range: range) }
            
            let dictionary = try await group.reduce(into: [SyntaxType: [NSRange]]()) {
                $0.merge($1, uniquingKeysWith: +)
            }
            
            return try Highlight.highlights(dictionary: dictionary)
        }
    }
    
    
    
    // MARK: Private Methods
    
    /// Extracts ranges of nestable items such as comments and quotes in the parse range.
    ///
    /// - Parameters:
    ///   - string: The string to parse.
    ///   - range: The range where to parse.
    /// - Throws: CancellationError.
    private func extractNestables(string: String, range parseRange: NSRange) throws -> [SyntaxType: [NSRange]] {
        
        let positions: [NestableItem] = try self.nestables.flatMap { (token, type) -> [NestableItem] in
            try Task.checkCancellation()
            
            switch token {
                case .inline(let delimiter):
                    return string.ranges(of: delimiter, range: parseRange)
                        .flatMap { range -> [NestableItem] in
                            let lineEnd = string.lineContentsEndIndex(at: range.upperBound)
                            let endRange = NSRange(location: lineEnd, length: 0)
                            
                            return [NestableItem(type: type, token: token, role: .begin, range: range),
                                    NestableItem(type: type, token: token, role: .end, range: endRange)]
                        }
                    
                case .pair(let pair):
                    if pair.begin == pair.end {
                        return string.ranges(of: pair.begin, range: parseRange)
                            .map { NestableItem(type: type, token: token, role: [.begin, .end], range: $0) }
                    } else {
                        return string.ranges(of: pair.begin, range: parseRange)
                            .map { NestableItem(type: type, token: token, role: .begin, range: $0) }
                        + string.ranges(of: pair.end, range: parseRange)
                            .map { NestableItem(type: type, token: token, role: .end, range: $0) }
                    }
            }
        }
            .filter { !string.isCharacterEscaped(at: $0.range.location) }  // remove escaped ones
            .sorted {  // sort by location
                if $0.range.location < $1.range.location { return true }
                if $0.range.location > $1.range.location { return false }
                
                if $0.range.isEmpty { return true }
                if $1.range.isEmpty { return false }
                
                return $0.range.length > $1.range.length
            }
        
        guard !positions.isEmpty else { return [:] }
        
        try Task.checkCancellation()
        
        // find pairs in the parse range
        var highlights: [SyntaxType: [NSRange]] = [:]
        var seekLocation = parseRange.location
        var index = 0
        
        while index < positions.endIndex {
            let beginPosition = positions[index]
            index += 1
            
            guard
                beginPosition.role.contains(.begin),
                beginPosition.range.location >= seekLocation
            else { continue }
            
            // search corresponding end delimiter
            guard let endIndex = positions[index...].firstIndex(where: {
                $0.role.contains(.end) && $0.token == beginPosition.token
            }) else { continue }  // give up if no end delimiter found
            
            let endPosition = positions[endIndex]
            let range = NSRange(beginPosition.range.lowerBound..<endPosition.range.upperBound)
            
            highlights[beginPosition.type, default: []].append(range)
            
            seekLocation = range.upperBound
            index = endIndex
        }
        
        return highlights
    }
}
