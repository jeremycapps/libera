export type AnswerType = "value" | "verdict" | "transform";
export type AnswerPath = "meaning" | "execution";
export type Density = 1 | 2 | 3;
export type Structure = "dimension" | "group" | "sequence";
export type SequenceKind = "temporal" | "dependency" | "trace";

export interface OperationDescriptorV1 {
  id: string;
  label: string;
  invocation: "model-operation" | "host-callback";
  reference: string;
  inputSchema?: Record<string, unknown>;
  confirmation?: string;
}

export interface ValueAnswer { type: "Value"; value: unknown; evidence?: unknown }

export interface LegacyBooleanVerdictV0 {
  type: "Verdict";
  contract: "LegacyBooleanVerdictV0";
  conforms: boolean;
  state?: never;
  finding?: unknown;
  reason?: unknown;
  expected?: unknown;
  actual?: unknown;
  evidence?: unknown;
}

export interface BoundedVerdictV1 {
  type: "Verdict";
  contract: "BoundedVerdictV1";
  state: string;
  conforms?: boolean;
  finding?: unknown;
  reason?: unknown;
  expected?: unknown;
  actual?: unknown;
  evidence?: unknown;
}

export interface TransformV1 {
  type: "Transform";
  operation: { id: string; name: string };
  input: unknown;
  output: unknown;
  before?: unknown;
  after?: unknown;
  evidence?: unknown;
}

export type FaciaItem = ValueAnswer | LegacyBooleanVerdictV0 | BoundedVerdictV1 | TransformV1;

export interface FaciaAnswerSetV1<T extends FaciaItem = FaciaItem> {
  schema: "facia.answer-set/1";
  question: string;
  answerType: AnswerType;
  path: AnswerPath;
  density: Density;
  inspection: "none" | "available";
  actionable: boolean;
  items: [T, ...T[]];
  structure?: Structure;
  sequenceKind?: SequenceKind;
  operations: OperationDescriptorV1[];
  trace?: unknown;
}

export type ValidationErrorCode =
  | "ANSWER_SET_SCHEMA_UNSUPPORTED" | "ANSWER_SET_EMPTY_ITEMS" | "ANSWER_KIND_MISMATCH"
  | "INVALID_DENSITY" | "SINGULAR_STRUCTURE_FORBIDDEN" | "SEQUENCE_KIND_REQUIRED"
  | "SEQUENCE_KIND_FORBIDDEN" | "ACTIONABILITY_MISMATCH" | "DUPLICATE_OPERATION_ID"
  | "INVALID_OPERATION_DESCRIPTOR" | "INVALID_ANSWER_SET";

export type ValidationResult = { valid: true; value: FaciaAnswerSetV1 } |
  { valid: false; errors: Array<{ code: ValidationErrorCode; path: string; message: string }> };

export function validateAnswerSet(value: unknown): ValidationResult;
export function resolveShape(value: unknown): object;
export function resolvePattern(shape: object, value: unknown): object;
export function resolveAffordances(value: unknown, shape?: object): object;
export function toComponentRecipe(pattern: object, affordances: object, value: unknown): object;
