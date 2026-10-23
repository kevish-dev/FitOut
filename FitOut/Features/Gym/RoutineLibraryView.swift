import SwiftUI

struct MyRoutinesView: View {
    @Bindable var store: GymStore
    var unit: WeightUnit = .kg
    @State private var editing: Routine?
    @State private var creating = false
    @State private var deleting: Routine?
    @State private var archiving: Routine?
    @State private var deletingDraft: RoutineDraft?

    var body: some View {
        List {
            Section {
                Button { creating = true } label: { Label("New routine", systemImage: "plus") }
                .accessibilityIdentifier("newRoutine")
            }
            if !store.drafts.isEmpty {
                Section("Continue editing") {
                    ForEach(store.drafts) { draft in
                        Button { editing = draft.routine } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(draft.routine.name.isEmpty ? "Untitled draft" : draft.routine.name).font(FitTheme.section(15))
                                Text("Draft · \(draft.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(FitTheme.body(12)).foregroundStyle(.secondary)
                            }.padding(.vertical, 5)
                        }
                        .swipeActions { Button("Discard", role: .destructive) { deletingDraft = draft } }
                    }
                }
            }
            if store.routines.isEmpty {
                Section {
                    ContentUnavailableView("Your week, your routine", systemImage: "calendar.badge.plus", description: Text("Start from a template or choose your own training days. Drafts are kept until you finish."))
                }
            }
            Section("Routines") {
                ForEach(store.routines.filter { $0.archivedAt == nil }) { routine in routineRow(routine) }
            }
            if store.routines.contains(where: { $0.archivedAt != nil }) {
                Section("Archived") {
                    ForEach(store.routines.filter { $0.archivedAt != nil }) { routine in routineRow(routine) }
                }
            }
        }
        .navigationTitle("My routines")
        .sheet(item: $editing) { RoutineEditor(store: store, routine: $0, unit: unit) }
        .sheet(isPresented: $creating) { RoutineCreationSheet(store: store, unit: unit, useAsActive: store.activeRoutine == nil) }
        .confirmationDialog("Delete this routine?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete routine", role: .destructive) { if let deleting { store.deleteRoutine(deleting.id) }; deleting = nil }
        } message: { Text("The routine and its draft will be removed. Workout history stays saved.") }
        .confirmationDialog("Archive this routine?", isPresented: Binding(get: { archiving != nil }, set: { if !$0 { archiving = nil } }), titleVisibility: .visible) {
            Button("Archive routine") {
                if var value = archiving { value.archivedAt = .now; value.isActive = false; store.save(value) }
                archiving = nil
            }
        } message: { Text("It will stop being active. You can restore it later; workout history is kept.") }
        .confirmationDialog("Discard this draft?", isPresented: Binding(get: { deletingDraft != nil }, set: { if !$0 { deletingDraft = nil } })) {
            Button("Discard draft", role: .destructive) { if let deletingDraft { store.discardDraft(deletingDraft.id) }; deletingDraft = nil }
        }
        .alert("Could not update routine", isPresented: Binding(get: { store.error != nil && editing == nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK", role: .cancel) { store.error = nil }
        } message: { Text(store.error ?? "") }
    }

    private func routineRow(_ routine: Routine) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button { editing = routine } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        if routine.isActive { Image(systemName: "checkmark.circle.fill").foregroundStyle(FitTheme.dashboardAccent) }
                        Text(routine.name).font(FitTheme.section(16))
                    }
                    Text("\(routine.trainingDays.count) training days · \(routine.isActive ? "Active" : routine.archivedAt == nil ? "Saved" : "Archived")")
                        .font(FitTheme.body(12)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, minHeight: 52, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Menu {
                Button("Edit") { editing = routine }
                if routine.archivedAt != nil {
                    Button("Restore") { var value = routine; value.archivedAt = nil; store.save(value) }
                } else if !routine.isActive {
                    Button("Use routine") {
                        if let error = store.readinessError(for: routine) { store.error = error }
                        else { var value = routine; value.isActive = true; store.save(value) }
                    }
                }
                Button("Duplicate") { store.save(routine.duplicate()) }
                if routine.archivedAt == nil { Button("Archive") { archiving = routine } }
                Button("Delete", role: .destructive) { deleting = routine }
            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
            .accessibilityLabel("Options for \(routine.name)")
        }
    }
}
