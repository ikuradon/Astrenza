import SwiftUI
import UniformTypeIdentifiers

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

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Camera", isPresented: $isCameraPresented, titleVisibility: .visible) {
                Button("Open Camera") {}
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Camera capture is mocked in this compose prototype.")
            }
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { _ in }
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
        onSelectDraft: @escaping (ComposeDraft) -> Void
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
                onSelectDraft: onSelectDraft
            )
        )
    }
}
