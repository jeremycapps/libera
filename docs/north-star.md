# Libera Product North Star

This is Libera.

Libera is a page-based platform for composing, sharing, and deploying executable semantic models.

The goal is to make collaborative semantic models feel as natural to author as notes, as practical to organize as a team workspace, and as easy to deploy as an application. A model should not be trapped inside a codebase, a whiteboard, a task manager, or a single agent session. It should be a durable page that humans can read, teams can improve, agents can execute, and systems can depend on.

# North Star

Write models as pages. Link them like a vault. Compose them like a workspace. Deploy them like apps.

Libera exists so people can build shared models of how work, time, coordination, interfaces, verification, and execution should behave. These models are closer to semantic models and ontologies than machine-learning weights. They describe meaning, structure, rules, roles, states, transitions, evidence, and authority. Libera makes those models executable.

# The Product Triangle

Libera combines three familiar product instincts.

Obsidian contributes the vault: local-readable markdown pages, links, backlinks, durable knowledge, and a graph of meaning.

Notion contributes the workspace: approachable composition, structured pages, templates, team editing, reusable systems, and everyday usability.

Vercel contributes deployment: preview, versioning, promotion, rollback, hosted runtime boundaries, endpoints, and shareable live artifacts.

The result is a vault of semantic pages that can be linked like notes, structured like a workspace, and deployed like software.

# Foundational Unit: Page

The foundational authoring unit is the page.

A page is the smallest durable unit that can be read by a human, linked by a vault, compiled by the runtime, and shared across a team.

A Libera page combines a markdown body with executable metadata. The markdown explains the model, its intent, examples, context, and design rationale. The metadata declares how the runtime should treat the page: what kind of model it is, what it imports, what it exports, what it verifies, and how it participates in execution.

A page can describe a contract, verifier, workflow, policy, decision, status, state transition, interface model, time model, or strategy model.

# Shareable Unit: Model Package

The shareable unit is the model package.

A model package is a versioned collection of pages, schemas, examples, tests, and runtime metadata. It is not merely a template. A template gives structure. A model package gives vocabulary, rules, verification, state behavior, write policy, examples, tests, and deployment behavior.

Example packages might include @domain/project-manager, @core/time, @material/ui-model, @domain/decision-feed, @corus/candidate-evaluation, or @facia/calendar-surface.

Packages should be importable, remixable, forkable, testable, and deployable. A team should be able to depend on a shared model the same way developers depend on a library, but with source material that remains legible to non-developers.

# Live Unit: Deployment

The live unit is the deployment.

A deployment is a model package running behind a usable boundary. That boundary might be an API, an MCP server, a CLI command, a team workspace, a document workflow, a calendar assistant, a decision feed, or an interface surface.

Deployment turns semantic pages into operational systems. It answers: what version is live, what inputs are accepted, what runtime is used, what state is admitted, what outputs are produced, and what can be rolled back.

# Technical Spine

The product architecture can be summarized as Page to Package to Deployment.

Pages are the human-readable source units. Packages are the collaborative distribution units. Deployments are the live runtime units.

Under the product surface, Libera provides the deterministic runtime. Its kernel evaluates normalized expressions against property environments using the simple principle Value\_out \= Evaluate(Expression, Props). Domain is one protocol that can be compiled onto that runtime: Contract to Result to Verdict to CurrentState to Snapshot. Address records where values belong and what transition occurred. Strategy will later choose candidates, repairs, retries, heuristics, and escalations when convergence fails.

This preserves a strict boundary: the kernel evaluates expressions, but it does not know what a contract or verdict means. Domain supplies coordination semantics. Address supplies structural writes. Strategy supplies search and response. The page-based platform supplies authoring, collaboration, sharing, and deployment.

# Why This Matters

Most work systems ask teams to manage tasks, documents, or apps. Libera asks teams to share the models underneath the work.

A project manager model can define decisions, commitments, owners, status, exceptions, meeting transitions, and verification rules. A time model can define cycles, phases, timestamps, observation boundaries, and calendar behavior. A UI model can define how semantic state becomes usable surfaces. These models can be reused across teams, adapted locally, tested against examples, and deployed into tools.

This is the difference between sharing a workflow description and sharing an executable model of the workflow.

# Positioning

Libera is not a knowledge graph platform, a model-weight registry, or another task manager.

Libera is a collaborative platform for executable semantic models.

Its promise is: author the model as a page, share it as a package, deploy it as a system.

The simplest product sentence is:

Libera is Notion plus Obsidian plus Vercel for semantic models.

The more precise sentence is:

Libera is a page-based platform for composing and deploying shared semantic models.

The North Star is:

Write the model once. Share the meaning. Deploy the behavior.  
