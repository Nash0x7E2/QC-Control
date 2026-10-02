import CoreBluetooth

enum BluetoothAvailability: Equatable, Sendable {
 case idle, waitingForPermission, ready, poweredOff, denied, unavailable
}

/// Construct only after the user chooses to look for headphones.
@MainActor final class BluetoothAccess: NSObject, CBCentralManagerDelegate {
 private var manager: CBCentralManager!
 private let update: (BluetoothAvailability) -> Void
 init(update: @escaping (BluetoothAvailability) -> Void) {
  self.update = update
  super.init()
  manager = CBCentralManager(delegate: self, queue: .main)
 }
 nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
  let availability: BluetoothAvailability
  if CBCentralManager.authorization == .denied || CBCentralManager.authorization == .restricted {
   availability = .denied
  } else {
   switch central.state {
   case .poweredOn: availability = .ready
   case .poweredOff: availability = .poweredOff
   case .unauthorized: availability = .denied
   case .unsupported: availability = .unavailable
   default: availability = .waitingForPermission
   }
  }
  Task { @MainActor [weak self] in self?.update(availability) }
 }
}
