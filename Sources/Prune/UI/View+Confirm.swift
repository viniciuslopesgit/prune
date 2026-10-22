import SwiftUI

extension View {
    func confirm(_ title: String, isPresented: Binding<Bool>, message: String, button: String, action: @escaping () -> Void) -> some View {
        confirmationDialog(title, isPresented: isPresented, titleVisibility: .visible) {
            Button(button, role: .destructive, action: action)
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(message)
        }
    }
}
