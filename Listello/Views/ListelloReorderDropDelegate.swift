import SwiftUI

struct ListelloReorderDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var draggedID: UUID?
    @Binding var lastTargetID: UUID?
    let move: (UUID, UUID) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        draggedID != nil
    }

    func dropEntered(info: DropInfo) {
        guard
            let draggedID,
            draggedID != targetID,
            lastTargetID != targetID
        else { return }

        lastTargetID = targetID
        move(draggedID, targetID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedID = nil
        lastTargetID = nil
        return true
    }
}
