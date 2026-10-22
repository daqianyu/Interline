# AGENTS.md — Interline

## Required plan-driven workflow

This section applies to every subsequent development, repair, optimization, and
acceptance task in this repository. It supplements the product principles below.

1. Read `plans/README.md`, then the active plan's `00-roadmap.md`, relevant
   requirements, development design, test design, and acceptance record before editing.
2. Follow the numbered execution order. Select the earliest actionable unfinished
   item and cite its requirement ID in the work summary and PR. If a dependency is
   blocked, record the evidence and continue only with a later independent item.
3. Before implementation, make the affected requirement, migration/rollback behavior,
   and acceptance cases concrete. If scope changes, update the plan first. A new
   user instruction takes precedence; reconcile it into the active plan.
4. Implement one coherent step at a time. Preserve user changes, text anchors,
   backward compatibility, and original data. Do not silently replace the planned
   outcome with a partial implementation or add unrelated features.
5. Run the checks required by `03-test-acceptance-design.md`. Distinguish implemented,
   compiled, automatically tested, visually inspected, and physically tested states.
   A simulator pass or unsigned IPA is not physical-device acceptance.
6. Update `00-roadmap.md`, `04-final-acceptance.md`, and `05-execution-log.md` with
   actual changed files, test/run evidence, limitations, and the next actionable ID.
   Never mark an item verified or the release accepted without matching evidence.
7. Keep changes in reviewable commits/PRs. Follow the user's existing GitHub
   authorization; this document does not introduce an extra confirmation gate.
   On 2026-10-23 the user explicitly authorized continuing publication of D05 and
   subsequent established-plan code, tests, and plan records to the public
   `daqianyu/Interline` repository, and merging after verification passes.
   This standing authorization applies within that plan and destination.
8. End each delivery with completed IDs, validation, remaining blockers, and the
   next step. Plans must live in the repository and remain readable without chat history.

The active plan is `plans/2026-10-improvements/`. Do not create a competing
lowercase `agent.md`; this `AGENTS.md` is the canonical agent instruction file.



\## 1. Project Identity



Build a polished native iOS novel-reading application.



\- Platform: iOS only.

\- Minimum deployment target: iOS 27.

\- Preferred UI framework: SwiftUI.

\- Primary language: Swift.

\- Product references: Apple Books, WeRead (微信读书), and Qidian Reading (起点读书).

\- Product priorities: reading comfort, interaction quality, visual consistency, and maintainable implementation.



The product must feel like a carefully designed native Apple application, not a generic AI-generated interface or a web application wrapped in an iOS shell.



\## 2. Non-Negotiable Product Principles



Always prioritize:



1\. Reading comfort over visual decoration.

2\. Clear and predictable interactions over novelty.

3\. Native iOS conventions over custom UI reinvention.

4\. Consistent design over isolated visual effects.

5\. Functional completeness over the number of features.



Keep the interface minimal, refined, quiet, and readable.



Do not introduce AI-themed visual decoration, unnecessary gradients, glowing borders, decorative dashboards, excessive floating buttons, or meaningless animations.



Do not add AI features, social feeds, rankings, advertisements, or monetization features unless explicitly requested.



\## 3. Design Direction



\### Visual identity



Use a modern Apple-native visual language with natural hierarchy, restrained colors, generous whitespace, and carefully considered typography.



The intended balance is:



\- Native Apple interface conventions.

\- A refined and content-focused reading experience.

\- Practical reading interactions inspired by mature reading applications.

\- Selective use of Liquid Glass.

\- Minimal visual noise.



Do not copy competitor interfaces directly. Adapt proven interaction principles to a consistent original design system.



\### Color



\- Prefer semantic system colors where appropriate.

\- Define reusable semantic color tokens.

\- Use one restrained accent color for important actions and selected states.

\- Keep ordinary text and content areas neutral.

\- Maintain clear contrast in both light and dark appearances.

\- Define reading backgrounds independently from general application backgrounds.

\- Never rely on color alone to communicate a state.



\### Typography



\- Optimize for long-form Chinese text.

\- Prefer native iOS font rendering and appropriate Chinese font fallbacks.

\- Use consistent typography tokens for headings, metadata, body text, chapter titles, and controls.

\- Support appropriate font-size and line-spacing adjustments.

\- Avoid cramped paragraphs, excessively small text, and inconsistent line heights.

\- Treat reading text as the primary visual content.



\### Spacing and components



\- Use a consistent spacing scale based on multiples of 4pt where practical.

\- Define reusable corner-radius, typography, and component tokens.

\- Avoid unnecessary cards, shadows, borders, and rounded containers.

\- Give interactive controls clear hierarchy and adequate touch targets.

\- Do not introduce new visual patterns without a clear design reason.



\## 4. Liquid Glass Policy



Use Liquid Glass selectively and only where it supports interaction or hierarchy.



Preferred locations:



\- Appropriate navigation controls.

\- Reader toolbars shown on demand.

\- Floating reading controls.

\- Suitable settings panels.



Rules:



\- Prefer officially supported APIs available in the verified target SDK.

\- Verify API names, availability, and behavior before implementation.

\- Do not invent APIs or assume that an API exists because it appears in an example.

\- Do not apply glass to every card, list, or content container.

\- Never permanently cover reading text with unnecessary glass controls.

\- Ensure controls remain legible over different backgrounds.

\- Respect native system behavior and accessibility settings.

\- Do not build a custom glass simulation unless there is a clear requirement and the native alternative is insufficient.



When the reader is in its immersive state, nonessential controls must be hidden.



\## 5. Core Product Experience



\### Bookshelf



The bookshelf is organized around continuing reading.



Prioritize:



1\. The most recently read book.

2\. A clear Continue Reading action.

3\. Book cover, title, author, and useful progress information.

4\. A clean collection of other saved books.

5\. Search and basic library management.



Do not let promotional content or secondary features compete with the Continue Reading action.



\### Reader



The reader is the core of the product.



\- Enter immersive reading mode by default.

\- Hide nonessential controls until requested.

\- Allow the reading toolbar to be shown and dismissed predictably.

\- Preserve reading position when opening and closing controls.

\- Provide table of contents, reading settings, bookmarks, progress navigation, and chapter navigation.

\- Support readable Chinese typography and long-form content.

\- Persist reading progress and restore it when the book is reopened.

\- Keep chapter state, reading position, and progress UI synchronized.



\### Reading settings



Support, at minimum:



\- Font size.

\- Line spacing.

\- Reading background.

\- Reading mode, where implemented.



Settings should take effect immediately and persist across launches.



Only expose functionality that actually works. If a system-level capability is unavailable or restricted, explain the limitation and implement an honest alternative where appropriate.



\### Other pages



The first release includes:



\- Book details.

\- Table of contents.

\- Local book search.

\- Basic bookshelf management.



Keep these pages visually consistent with the bookshelf and reader.



\## 6. Interaction Rules



Every visible interactive control must have a real, meaningful action.



Do not create decorative buttons that do nothing.



Important flows must work end to end:



\- Open a book from the bookshelf.

\- Start or continue reading.

\- Show and hide reader controls.

\- Change font size, line spacing, and reading background.

\- Navigate to a chapter from the table of contents.

\- Navigate between adjacent chapters.

\- Add and remove bookmarks.

\- Change reading progress.

\- Restore reading progress after relaunch.

\- Search local sample books.

\- Add and remove books from the bookshelf.



Avoid unexpected gesture conflicts with scrolling, system navigation, and accessibility interactions.



\## 7. Engineering Principles



\- Use SwiftUI and native frameworks by default.

\- Verify the actual Xcode version, SDK, deployment target, and API availability.

\- Separate views, models, state management, persistence, and sample data.

\- Keep view implementations reasonably focused.

\- Avoid unnecessary abstractions and third-party dependencies.

\- Use stable identifiers for books, chapters, and bookmarks.

\- Avoid duplicating business logic across views.

\- Keep reading progress and preferences consistent across the application.

\- Handle empty states, invalid data, and persistence failures.

\- Use stable reading-position anchors where appropriate instead of relying exclusively on absolute pixel offsets.

\- Keep sample content separate from production data access.

\- Respect accessibility, Dynamic Type where appropriate, VoiceOver, and Reduce Motion.



Do not change the project's architecture or add dependencies without a concrete benefit.



\## 8. Quality and Verification



Never claim that something works unless it has been implemented and verified to the extent stated.



After making changes:



1\. Inspect the relevant existing code before editing.

2\. Implement the smallest coherent change.

3\. Build using the available target environment.

4\. Run relevant tests.

5\. Inspect the UI in a simulator when available.

6\. Verify affected interaction flows.

7\. Fix regressions introduced by the change.



If the target SDK or simulator is unavailable, state exactly what could not be verified.



Distinguish clearly between:



\- Implemented.

\- Built successfully.

\- Tested successfully.

\- Visually inspected.

\- Not yet verified.



Do not fabricate screenshots, build results, test results, or simulator observations.



\## 9. Working Process



For substantial tasks:



1\. Inspect the existing project and applicable rules.

2\. Summarize the goal and affected areas.

3\. Identify relevant design and architectural constraints.

4\. Implement in small, coherent steps.

5\. Validate the result.

6\. Report changes, verification results, and remaining issues.



For visual changes, preserve the established design system.



For bug fixes, avoid unrelated redesigns.



For new features, reuse existing patterns and tokens before introducing new ones.



Do not rebuild working parts of the application without a clear reason.



\## 10. Scope Control



The first release is a local, functional MVP.



Use fictional sample books and original sample chapter content unless authorized content is explicitly provided.



Do not introduce backend services, user accounts, cloud synchronization, purchases, subscription systems, social features, or online book catalogs unless explicitly requested.



Keep the data layer replaceable so that future features can be added without rewriting the reader.



\## 11. Definition of Done



A task is complete only when:



\- The requested behavior is implemented.

\- The design remains consistent with this document.

\- Relevant edge cases are considered.

\- The result has been verified to the extent possible.

\- Known limitations are reported honestly.

\- No unnecessary unrelated changes have been introduced.



For the first MVP, prioritize a polished bookshelf, a reliable immersive reader, correct reading-position restoration, usable reading settings, and consistent native interactions.



When requirements conflict, preserve reading comfort, correctness, and native iOS behavior first.


