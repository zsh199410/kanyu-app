import SwiftUI

/// Present as a sheet. This stack belongs to the modal, never to a pushed destination.
/// The shared PeopleStore remains the single source of selection and persistence.
struct V5PersonPicker: View {
    @EnvironmentObject private var people: PeopleStore
    @EnvironmentObject private var router: V5Router
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    private var matches: [Person] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return people.people }
        return people.people.filter {
            $0.name.localizedCaseInsensitiveContains(term) ||
            $0.relation.localizedCaseInsensitiveContains(term) ||
            $0.id.uuidString.localizedCaseInsensitiveContains(term) ||
            DisplayTimeReceipt.beijing($0.birthDate).localizedCaseInsensitiveContains(term)
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: V5Metric.gap) {
                    if people.people.isEmpty {
                        V5StatusPanel(state: .empty, title: "尚未建档", message: "建立真实人物档案后，即可在这里切换命主。")
                    } else {
                        Text("核对生辰与档案编号，选择本次测算的人物。")
                            .font(V5Typography.evidence).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
                        if matches.isEmpty {
                            V5StatusPanel(state: .empty, title: "没有匹配的档案", message: "可搜索姓名、关系、生辰或档案编号。")
                        }
                        ForEach(matches) { person in
                            choice(person)
                        }
                    }
                    Button {
                        dismiss()
                        router.tab = 3
                    } label: {
                        Label("管理人物档案", systemImage: "person.2")
                            .frame(maxWidth: .infinity, minHeight: V5Metric.target)
                    }.buttonStyle(.plain).font(V5Typography.detail)
                }.padding(V5Metric.page)
            }
            .background { V5SceneBackground() }
            .foregroundStyle(V5Palette.color(V5Palette.current.ink))
            .navigationTitle("切换命主").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "搜索姓名、关系或档案编号")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }.frame(minWidth: V5Metric.target, minHeight: V5Metric.target)
                }
            }
            .accessibilityIdentifier("v5.person.picker")
        }
        .tint(V5Palette.color(V5Palette.current.accent))
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
    private func choice(_ person: Person) -> some View {
        let selected = people.currentPerson?.id == person.id
        let hasNamesake = people.people.filter { $0.name == person.name }.count > 1
        return Button {
            // Resolve the UUID again when tapped: a deleted row must never restore
            // an obsolete snapshot or select a different person with the same name.
            guard let current = people.people.first(where: { $0.id == person.id }) else { return }
            people.setCurrentPerson(current)
            dismiss()
        } label: {
            V5Card {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(displayName(person)).font(.system(.title3, design: .serif).weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(details(person)).font(V5Typography.evidence)
                            .foregroundStyle(V5Palette.color(V5Palette.current.secondary))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("档案 \(person.id.uuidString.prefix(8))").font(.caption.monospaced())
                            .foregroundStyle(V5Palette.color(V5Palette.current.secondary))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title2).foregroundStyle(V5Palette.color(V5Palette.current.accent))
                        .accessibilityHidden(true)
                }.frame(maxWidth: .infinity, minHeight: V5Metric.target, alignment: .leading)
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        // Preserve the existing unique-name action label as a real accessibility
        // contract. Namesakes receive the actual distinguishing birth/UUID receipt.
        .accessibilityLabel(hasNamesake ? "选择命主：\(displayName(person))，\(details(person))，档案\(person.id.uuidString.prefix(8))" : "选择命主：\(displayName(person))")
        .accessibilityValue("\(selected ? "当前命主，" : "")\(details(person))，档案\(person.id.uuidString)")
        .accessibilityHint("设为当前命主并关闭选择窗口")
        .accessibilityIdentifier("v5.person.choice." + person.id.uuidString)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func displayName(_ person: Person) -> String { person.name.isEmpty ? "未命名" : person.name }
    private func details(_ person: Person) -> String {
        (person.relation.isEmpty ? "" : person.relation + " · ") + DisplayTimeReceipt.beijing(person.birthDate)
    }
}

/// Use around the existing visible person name/chevron in a hero or toolbar.
/// An empty library never exposes a meaningless "switch" action.
struct V5PersonPickerButton<Label: View>: View {
    @EnvironmentObject private var people: PeopleStore
    @State private var presenting = false
    let label: Label
    init(@ViewBuilder label: () -> Label) { self.label = label() }
    var body: some View {
        if let person = people.currentPerson {
            Button { presenting = true } label: {
                label.frame(minHeight: V5Metric.target).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("切换命主")
            .accessibilityIdentifier("v5.person.switch")
            .accessibilityValue(person.name + " · " + person.id.uuidString)
            .sheet(isPresented: $presenting) { V5PersonPicker() }
        }
    }
}
