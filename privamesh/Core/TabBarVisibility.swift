//
//  TabBarVisibility.swift
//  privamesh
//
//  Lets a pushed full-screen detail (e.g. a chat with its own bottom input bar)
//  hide the custom floating tab bar so the two don't overlap.
//

import Foundation

@Observable
final class TabBarVisibility {
    var hidden = false
}
