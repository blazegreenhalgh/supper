"""Select balanced UI suites, rejecting missing, stale or duplicate test assignments."""

import argparse
import json
import re
from collections import Counter
from pathlib import Path

# Balanced against passing run 35107921038: roughly 4.5–5 minutes of test
# execution per simulator, plus startup/teardown. Keep native animations and
# assertions intact. Add new tests here; CI fails if any test is left out.
SUITES = {
    "discovery": [
        "testDiscoveryEditsStayDraftUntilKeptAndGridSharesDecisions",
        "testDiscoverySwipeDiscardsAndKeeps",
        "testDiscoveryLoadingCanBeCancelledAndKeepsThePrompt",
        "testRecipeCardPreviewActionsAndCollectionSubmenu",
        "testLibraryDeletionRequiresConfirmationAndCloudCheckResponds",
    ],
    "chat": [
        "testChatCollectionChangesApplyToDraftAndOnlyPersistOnSave",
        "testRecipeChatKeepsInputWhenReopenedAndCancelDoesNotSave",
        "testRecipeChatPreviewShowsRemovalsAndAppliesAndUndoesInPlace",
        "testRecipeChatRetainsSessionAcrossEditorsAndProtectsManualChanges",
    ],
    "editor": [
        "testRecipePhotosPreviewOriginalAndApplyWithUndoAndUploadOption",
        "testFormattingReviewCancelAndDraftOnlyApply",
        "testIngredientAndSectionDragsPersistOnSave",
        "testFocusedIngredientEditorAndFullScreenMethod",
        "testEditorCancelKeepsRecipeAndSingleReactionControl",
        "testRecipeDragMovesBetweenHomeCollections",
    ],
    "library": [
        "testMainTagsCreateRenameDeleteAndIndividualEntry",
        "testTagsSheetAndSimpleGrocerySelection",
        "testNativeBackAndInteractiveTransitionsPreserveSearch",
        "testOpenAIKeyCanBeSavedReplacedAndRemovedWithoutSendingRequests",
        "testHomepageActionsAndActiveFilters",
        "testGroceriesCanClearCheckedAndUncheckedItems",
    ],
}
ROOT = Path(__file__).resolve().parents[2]


def validate(suites: dict[str, list[str]], source: str) -> None:
    tests = set(re.findall(r"\bfunc\s+(test\w+)\s*\(", source))
    assigned = Counter(test for suite in suites.values() for test in suite)
    missing = sorted(tests - assigned.keys())
    stale = sorted(assigned.keys() - tests)
    repeated = sorted(test for test, count in assigned.items() if count != 1)
    if not tests or not suites or any(not suite for suite in suites.values()) or missing or stale or repeated:
        raise ValueError(
            f"Every UI test must belong to exactly one nonempty suite. "
            f"Missing: {missing}; unknown: {stale}; duplicates: {repeated}"
        )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    selection = parser.add_mutually_exclusive_group(required=True)
    selection.add_argument("--matrix", action="store_true", help="Print the GitHub Actions matrix")
    selection.add_argument("--suite", choices=SUITES, help="Print xcodebuild test selection arguments")
    args = parser.parse_args()
    try:
        validate(SUITES, (ROOT / "Tests/UI/SupperUITests.swift").read_text())
    except ValueError as error:
        parser.error(str(error))
    if args.matrix:
        print(json.dumps({"suite": list(SUITES)}))
    else:
        for test in SUITES[args.suite]:
            print(f"-only-testing:SupperUITests/SupperUITests/{test}")
