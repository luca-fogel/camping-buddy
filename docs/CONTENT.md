# Offline seed content

`Resources/ReferenceLibrary/references.json` contains eight original development summaries, each with stable ID, title, text, search keywords, source title and URL, access date, region, rights, and review status. All sources were opened on 2026-09-05. These are development seed passages, not expert-reviewed production guidance or copies of complete NPS pages.

The initial audience is English-speaking beginners taking weekend camping trips in the northeastern United States. The sources provide general US guidance. No passage establishes a particular park's current rules or conditions. Change the audience and region metadata alongside editorial review when expanding scope.

| Bundled passage IDs | Primary reference | Page's displayed update date |
| --- | --- | --- |
| `trip-plan`, `check-local-rules` | [Before the Trip](https://www.nps.gov/subjects/camping/before-the-trip.htm) | 2024-07-02 |
| `essentials`, `offline-navigation` | [Ten Essentials](https://www.nps.gov/articles/10essentials.htm) | 2026-05-28 |
| `sleep-system` | [What to Bring](https://www.nps.gov/subjects/camping/what-to-bring.htm) | 2024-07-02 |
| `choose-campsite` | [Finding and Setting Up a Campsite](https://www.nps.gov/subjects/camping/finding-and-setting-up-a-campsite.htm) | 2020-12-02 |
| `food-storage` | [During Your Stay](https://www.nps.gov/subjects/camping/during-your-stay.htm) | 2016-09-06 |
| `meal-kit` | [Cooking in Camp](https://www.nps.gov/subjects/camping/cooking-in-camp.htm) | 2022-06-22 |

## Editorial and rights notes

The passages were written for this prototype; they are not NPS-authored or endorsed. No images, logos, full pages, or third-party excerpts are bundled. NPS distinguishes its government works from third-party material and protected marks in its [ownership notice](https://www.nps.gov/aboutus/disclaimer.htm), checked 2026-09-05. No claim is made to original US Government works. The Ten Essentials page credits the underlying system to The Mountaineers; that attribution is retained in the relevant record.

The app's local source view should show the bundled summary and its metadata without navigating to the website. URLs identify provenance for later checking; network access must not be required to read a citation. An access date records retrieval for this development snapshot, not an assertion that the advice is current indefinitely.

General NPS pages give differing backcountry food-separation distances. This seed intentionally avoids a universal distance and directs campers to the destination's requirements. It also excludes medical treatment, wild-food identification, current weather, closures, and detailed stove operation. Unsupported questions require a clear limit instead of a plausible answer.

## Held-out evaluation

`evaluation/scenarios.json` is evaluation input, not training data. Keep it out of Studio training and retrieval resources. It contains ten questions with `expectedSourceIDs` and a plain-language `expectedBehavior` rubric; the app should not load these expected answers as generation context. Source IDs are the minimum relevant passages expected when retrieval runs. An empty list means there is no supporting passage; it does not permit using unrelated material as evidence.

For each model and prompt version, record retrieved IDs, generated answer, validated citations, and a human assessment of support, usefulness, uncertainty, and scope. Record model revision and generation settings. A valid citation ID only establishes that a passage exists; a reviewer must also check whether the passage supports the nearby claim. Do not equate successful retrieval or valid formatting with answer correctness.

Run the same held-out questions for base model, base plus retrieval, and any later camping adapter plus retrieval. Retain failures without silently rewriting this set to match outputs. Add a fresh held-out set before broader comparison if these questions guide model or prompt changes. The file supplies evaluation cases; it is not evidence that generation has passed them.

Before release, replace or review this development corpus with qualified outdoor reviewers, confirm reuse rights at the item level, add versioned park-specific coverage where appropriate, and define an update policy. A bigger corpus or fine-tune does not replace offline validation and evidence checks.
