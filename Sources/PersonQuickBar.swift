import SwiftUI

/// 人物一键调取横栏：一处建档，全院通用。
/// 点一下名字胶囊，即把该人的生辰／性别／出生地经度交给宿主页面，由宿主决定如何带入。
struct PersonQuickBar: View {
    @ObservedObject var store: PeopleStore
    var selectedID: UUID? = nil
    var onSelect: (Person) -> Void

    var body: some View {
        if store.people.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle.badge.plus").foregroundStyle(Ky.gold)
                Text("还没有人物档案——先到「人物档案」建一人，全院都能一键调取。".scriptConverted)
                    .font(.caption).foregroundStyle(Ky.sub)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Ky.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Label("调取：".scriptConverted, systemImage: "person.crop.rectangle.stack")
                        .font(.caption2).foregroundStyle(Ky.sub)
                    ForEach(store.people) { p in
                        let active = selectedID == p.id
                        Button { onSelect(p) } label: {
                            HStack(spacing: 4) {
                                Text(p.name.isEmpty ? "未命名".scriptConverted : p.name).fontWeight(active ? .bold : .medium)
                                Text(p.gender == "M" ? "男" : "女").opacity(0.75)
                            }
                            .font(.caption)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(active ? Ky.qingdai : Ky.elevated)
                            .foregroundStyle(active ? Color.white : Ky.ink)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(active ? Ky.qingdai : Ky.line, lineWidth: 0.7))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
