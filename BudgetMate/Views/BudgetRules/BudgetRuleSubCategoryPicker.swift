import SwiftUI
import SwiftData

struct BudgetRuleSubCategoryPicker: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BudgetRuleSubCategory.sortOrder) private var allSubCategories: [BudgetRuleSubCategory]

    @Binding var selectedSubCategory: BudgetRuleSubCategory?
    let orderGroup: BudgetRuleService.OrderGroup

    @State private var showNewSubCategory = false
    @State private var newSubCategoryTitle = ""

    private var subCategories: [BudgetRuleSubCategory] {
        BudgetRuleSubCategoryService.subCategories(for: orderGroup, from: allSubCategories)
    }

    var body: some View {
        Picker("Sub-category", selection: $selectedSubCategory) {
            Text("None").tag(nil as BudgetRuleSubCategory?)
            ForEach(subCategories, id: \.id) { subCategory in
                Text(subCategory.title).tag(subCategory as BudgetRuleSubCategory?)
            }
        }

        Button("New sub-category…") {
            newSubCategoryTitle = ""
            showNewSubCategory = true
        }
        .font(.caption)
        .alert("New sub-category", isPresented: $showNewSubCategory) {
            TextField("Name", text: $newSubCategoryTitle)
            Button("Add") { createSubCategory() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func createSubCategory() {
        guard let created = BudgetRuleSubCategoryService.addSubCategory(
            orderGroup: orderGroup,
            title: newSubCategoryTitle,
            existing: allSubCategories,
            in: modelContext
        ) else { return }
        selectedSubCategory = created
    }
}

extension BudgetRuleService.OrderGroup {
    static func forPicker(from type: BudgetType) -> BudgetRuleService.OrderGroup? {
        let group = forType(type)
        return group == .incoming || group == .outgoing ? group : nil
    }
}
