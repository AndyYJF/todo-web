export type Priority = "low" | "normal" | "high";

export interface Task {
  id: number;
  title: string;
  note: string;
  /** 格式 'YYYY-MM-DD HH:mm' 本地时间，null 表示未设置 */
  startAt: string | null;
  dueAt: string | null;
  done: 0 | 1;
  doneAt: string | null;
  priority: Priority;
  project: string;
  /** 快速任务（临时待办） */
  quick: 0 | 1;
  /** 置顶（磁贴模式） */
  pinned: 0 | 1;
  /** 外部同步源 ID（校园事务） */
  externalId: string | null;
  /** 上游 revision，回写状态时的版本校验 */
  externalRev: number | null;
  createdAt: string;
  updatedAt: string;
}

export interface TaskInput {
  title: string;
  note?: string;
  startAt?: string | null;
  dueAt?: string | null;
  priority?: Priority;
  project?: string;
  quick?: boolean;
  pinned?: boolean;
}

export type TaskPatch = Partial<Omit<TaskInput, "title">> & {
  title?: string;
  done?: boolean;
};
