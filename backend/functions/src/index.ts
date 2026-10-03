import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { CallableRequest, HttpsError, onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { setGlobalOptions } from "firebase-functions/v2/options";
import { Principal } from "./contracts";
import { KMSRecordingStore } from "./encryption";
import { CloudVoiceService } from "./service";
import { CloudTaskDispatcher } from "./tasks";
import { connection, operation, preserveCause } from "./diagnostics";
import { StoryGenerationService, VertexStoryProvider } from "./story";

initializeApp();
setGlobalOptions({ region: "europe-west1", maxInstances: 10, memory: "512MiB", timeoutSeconds: 120, serviceAccount: process.env.API_SERVICE_ACCOUNT });

function service(): CloudVoiceService {
  const project = process.env.GCLOUD_PROJECT ?? process.env.GCP_PROJECT ?? process.env.PROJECT_ID ?? "";
  return new CloudVoiceService(
    getFirestore(), new KMSRecordingStore(process.env.VOICE_BUCKET ?? "", process.env.KMS_KEY_NAME ?? ""),
    new CloudTaskDispatcher({ project, location: process.env.TASK_LOCATION ?? "europe-west1", queue: process.env.TASK_QUEUE ?? "bedtime-voice-worker", workerURL: process.env.WORKER_URL ?? "", serviceAccount: process.env.TASK_SERVICE_ACCOUNT ?? "" }),
    { enabled: () => process.env.ENABLE_CLOUD_NARRATION === "true" },
  );
}
async function principal(request: CallableRequest): Promise<Principal> {
  if (request.app?.alreadyConsumed) throw new HttpsError("permission-denied", "This request token was already used. Try again.");
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in with Apple to continue.");
  // Callable validation authenticates the ID token; this additional check rejects revoked/disabled accounts.
  const authorization = request.rawRequest.headers.authorization;
  if (!authorization?.startsWith("Bearer ")) throw new HttpsError("unauthenticated", "Sign in with Apple to continue.");
  let token;
  try { token = await connection("firebase_auth", "verify_id_token", () => getAuth().verifyIdToken(authorization.substring(7), true)); }
  catch (error) { throw preserveCause(new HttpsError("unauthenticated", "Sign in with Apple again to continue."), error); }
  if (token.uid !== request.auth.uid || token.firebase?.sign_in_provider !== "apple.com") throw new HttpsError("unauthenticated", "Sign in with Apple to continue.");
  return { uid: token.uid, provider: token.firebase.sign_in_provider, authTime: token.auth_time };
}
const secured = { enforceAppCheck: true, consumeAppCheckToken: true } as const;
export const beginVoiceEnrollment = onCall(secured, async (request) => operation("beginVoiceEnrollment", async () => service().beginVoiceEnrollment(await principal(request), request.data)));
export const uploadEnrollmentRecording = onCall(secured, async (request) => operation("uploadEnrollmentRecording", async () => service().uploadEnrollmentRecording(await principal(request), request.data)));
export const completeVoiceEnrollment = onCall(secured, async (request) => operation("completeVoiceEnrollment", async () => service().completeVoiceEnrollment(await principal(request), request.data)));
export const approveVoice = onCall(secured, async (request) => operation("approveVoice", async () => service().approveVoice(await principal(request), request.data)));
export const startNarration = onCall(secured, async (request) => operation("startNarration", async () => service().startNarration(await principal(request), request.data)));
export const cancelNarration = onCall(secured, async (request) => operation("cancelNarration", async () => service().cancelNarration(await principal(request), request.data)));
export const deleteVoice = onCall(secured, async (request) => operation("deleteVoice", async () => service().deleteVoice(await principal(request), request.data)));
export const deleteAccount = onCall(secured, async (request) => operation("deleteAccount", async () => service().deleteAccount(await principal(request), request.data)));
export const retryPendingDispatches = onSchedule({ schedule: "every 5 minutes", timeZone: "UTC", timeoutSeconds: 120 }, async () => operation("retryPendingDispatches", async () => service().retryPendingDispatches()));

export const generateStoryBook = onCall({ ...secured, timeoutSeconds: 360, maxInstances: 4, concurrency: 4 }, async (request) => operation("generateStoryBook", async () => {
  const owner = await principal(request);
  const project = process.env.GCLOUD_PROJECT ?? process.env.GCP_PROJECT ?? "";
  return new StoryGenerationService(getFirestore(), new VertexStoryProvider(project),
    { enabled: () => process.env.ENABLE_STORY_GENERATION === "true" }).generate(owner, request.data);
}));
