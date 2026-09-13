# Supper product decisions

## Purpose

Supper solves the “what do we cook?” problem by keeping a beautiful shared library of meals a household already likes and wants to make again.

## Core experience

1. Open Supper and visually browse meals.
2. Search/filter by title, ingredients, duration or tags.
3. Open a recipe for ingredients and method.
4. Add selected ingredients to the shared grocery list.
5. Add new recipes with as little as a photo + title, or import from a URL.

## Required

- Native SwiftUI feel inspired by Apple Invites.
- Image-first cards and large recipe hero imagery.
- System materials / blur transitions between imagery and content.
- Duration.
- Tags.
- Ingredients and method.
- Quick Add requiring only title; image is strongly encouraged but not mandatory.
- URL import.
- AI-assisted import/capture later, especially screenshots, cookbook photos and unstructured text.
- Individual reactions per household member.
- Shared recipes and grocery list via CloudKit.
- Grocery items can be selected from a recipe before adding.
- Offline-first local persistence with CloudKit used for sync.

## Deliberately excluded

- Meal history.
- “Cooked it” action.
- Last cooked date.
- Star/numeric ratings.
- Ongoing meal logging.
- Nutrition/macros.
- Pantry inventory for V1.
- Public/community recipe network.

## Near-term build order

1. Recipe library + detail polish.
2. Recipe create/edit.
3. URL import hardening.
4. Grocery ingredient combining.
5. CloudKit sharing invitation/acceptance UI.
6. Resolve household member identity for reactions.
7. Apple Foundation Models fallback for unstructured recipe extraction.
8. Screenshot/cookbook-photo extraction.
9. Smart “pick something” suggestions using duration/tags/reactions without meal-history data.
