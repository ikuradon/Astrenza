import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ComposeSheetPresentationModifier: ViewModifier {
    @Binding var isCameraPresented: Bool
    @Binding var isFileImporterPresented: Bool
    @Binding var isDraftCloseDialogPresented: Bool
    @Binding var isDraftsViewPresented: Bool
    let savedDrafts: [ComposeDraft]
    let onIgnoreDraft: () -> Void
    let onSaveDraft: () -> Void
    let onDeleteDrafts: (IndexSet) -> Void
    let onSelectDraft: (ComposeDraft) -> Void
    let onCameraImage: (UIImage) -> Void
    let onImportFiles: (Result<[URL], Error>) -> Void

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $isCameraPresented) {
                ComposeCameraPicker(onSelect: onCameraImage)
                    .ignoresSafeArea()
            }
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: [.image],
                allowsMultipleSelection: true
            ) { result in
                onImportFiles(result)
            }
            .confirmationDialog("", isPresented: $isDraftCloseDialogPresented, titleVisibility: .hidden) {
                Button("Ignore Draft", role: .destructive, action: onIgnoreDraft)
                Button("Save Draft", action: onSaveDraft)
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $isDraftsViewPresented) {
                ComposeDraftsView(
                    drafts: savedDrafts,
                    onDelete: onDeleteDrafts,
                    onSelect: onSelectDraft
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
            }
    }
}

extension View {
    func composeSheetPresentations(
        isCameraPresented: Binding<Bool>,
        isFileImporterPresented: Binding<Bool>,
        isDraftCloseDialogPresented: Binding<Bool>,
        isDraftsViewPresented: Binding<Bool>,
        savedDrafts: [ComposeDraft],
        onIgnoreDraft: @escaping () -> Void,
        onSaveDraft: @escaping () -> Void,
        onDeleteDrafts: @escaping (IndexSet) -> Void,
        onSelectDraft: @escaping (ComposeDraft) -> Void,
        onCameraImage: @escaping (UIImage) -> Void,
        onImportFiles: @escaping (Result<[URL], Error>) -> Void
    ) -> some View {
        modifier(
            ComposeSheetPresentationModifier(
                isCameraPresented: isCameraPresented,
                isFileImporterPresented: isFileImporterPresented,
                isDraftCloseDialogPresented: isDraftCloseDialogPresented,
                isDraftsViewPresented: isDraftsViewPresented,
                savedDrafts: savedDrafts,
                onIgnoreDraft: onIgnoreDraft,
                onSaveDraft: onSaveDraft,
                onDeleteDrafts: onDeleteDrafts,
                onSelectDraft: onSelectDraft,
                onCameraImage: onCameraImage,
                onImportFiles: onImportFiles
            )
        )
    }
}

private struct ComposeCameraPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera)
            ? .camera
            : .photoLibrary
        picker.mediaTypes = [UTType.image.identifier]
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIImagePickerController,
        context: Context
    ) {}

    final class Coordinator: NSObject,
        UIImagePickerControllerDelegate,
        UINavigationControllerDelegate {
        let parent: ComposeCameraPicker

        init(parent: ComposeCameraPicker) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(
            _ picker: UIImagePickerController
        ) {
            parent.dismiss()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onSelect(image)
            }
            parent.dismiss()
        }
    }
}
