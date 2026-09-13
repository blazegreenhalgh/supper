import CoreData

@objc(SupperLibraryMO)
final class SupperLibraryMO: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var createdAt: Date?
    @NSManaged var recipes: NSSet?
    @NSManaged var groceryItems: NSSet?
}

@objc(RecipeMO)
final class RecipeMO: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var title: String?
    @NSManaged var imageData: Data?
    @NSManaged var durationMinutes: NSNumber?
    @NSManaged var servings: NSNumber?
    @NSManaged var tagsJSON: String?
    @NSManaged var notes: String?
    @NSManaged var sourceURL: String?
    @NSManaged var createdAt: Date?
    @NSManaged var library: SupperLibraryMO?
    @NSManaged var ingredients: NSSet?
    @NSManaged var steps: NSSet?
    @NSManaged var reactions: NSSet?
}

@objc(IngredientMO)
final class IngredientMO: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var quantity: String?
    @NSManaged var unit: String?
    @NSManaged var order: NSNumber?
    @NSManaged var recipe: RecipeMO?
}

@objc(RecipeStepMO)
final class RecipeStepMO: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var text: String?
    @NSManaged var order: NSNumber?
    @NSManaged var recipe: RecipeMO?
}

@objc(ReactionMO)
final class ReactionMO: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var personID: String?
    @NSManaged var emoji: String?
    @NSManaged var recipe: RecipeMO?
}

@objc(GroceryItemMO)
final class GroceryItemMO: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var quantity: String?
    @NSManaged var unit: String?
    @NSManaged var isChecked: NSNumber?
    @NSManaged var sourceRecipeIDsJSON: String?
    @NSManaged var order: NSNumber?
    @NSManaged var library: SupperLibraryMO?
}
