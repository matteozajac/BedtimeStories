import { CloudTasksClient, protos } from "@google-cloud/tasks";
import { TaskDispatcher, WorkerTask } from "./contracts";
import { connection, diagnostic, taskKey } from "./diagnostics";

export interface QueueConfig { project: string; location: string; queue: string; workerURL: string; serviceAccount: string }
export class CloudTaskDispatcher implements TaskDispatcher {
  constructor(private config: QueueConfig, private client = new CloudTasksClient()) {}
  async enqueue(task: WorkerTask): Promise<void> {
    const { project, location, queue, workerURL, serviceAccount } = this.config;
    if (!project || !location || !queue || !serviceAccount || !workerURL.startsWith("https://")) throw new Error("Cloud task configuration is incomplete");
    const serviceURL = new URL(workerURL);
    if (serviceURL.pathname !== "/" || serviceURL.search || serviceURL.hash || serviceURL.username || serviceURL.password) throw new Error("Worker URL must be the Cloud Run service base URL");
    const audience = serviceURL.origin;
    const parent = this.client.queuePath(project, location, queue);
    const taskId = taskKey(task);
    try {
      await connection("cloud_tasks", "enqueue", () => this.client.createTask({
        parent,
        task: {
          name: `${parent}/tasks/${taskId}`,
          dispatchDeadline: { seconds: 1800 },
          httpRequest: {
            httpMethod: protos.google.cloud.tasks.v2.HttpMethod.POST,
            url: new URL("/tasks", serviceURL).href,
            headers: { "Content-Type": "application/json" },
            body: Buffer.from(JSON.stringify(task)),
            oidcToken: { serviceAccountEmail: serviceAccount, audience },
          },
        },
      }), { task_key: taskId, task_kind: task.kind });
    } catch (error) {
      if ((error as { code?: number }).code !== 6) throw error; // ALREADY_EXISTS: same durable operation.
      diagnostic("debug", "cloud_task_already_enqueued", { task_key: taskId, task_kind: task.kind });
    }
  }
}
