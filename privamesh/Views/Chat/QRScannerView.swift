//
//  QRScannerView.swift
//  privamesh
//
//  DataScannerViewController wrapper for QR code scanning (iOS 17+).
//

import SwiftUI

#if os(iOS)
import VisionKit
import Vision

struct QRScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            isHighlightingEnabled: true
        )
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        private var scanned = false

        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            guard !scanned, case let .barcode(barcode) = item,
                  let payload = barcode.payloadStringValue else { return }
            scanned = true
            dataScanner.stopScanning()
            onScan(payload)
        }
    }
}
#endif
