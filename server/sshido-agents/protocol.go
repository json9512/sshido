package main

const (
	KindUser       = "user"
	KindReply      = "reply"
	KindProgress   = "progress"
	KindDone       = "done"
	KindNeedsInput = "needs_input"
	KindError      = "error"
	KindFile       = "file"
)

const (
	RoleOrchestrator = "orchestrator"
	RoleWorker       = "worker"
)

const (
	StatusStarting = "starting"
	StatusWorking  = "working"
	StatusIdle     = "idle"
	StatusFailed   = "failed"
	StatusStopped  = "stopped"
)

type Message struct {
	ID         int64       `json:"id"`
	AgentID    string      `json:"agentId,omitempty"`
	Author     string      `json:"author"`
	Kind       string      `json:"kind"`
	Text       string      `json:"text"`
	CreatedAt  int64       `json:"createdAt"`
	Attachment *Attachment `json:"attachment,omitempty"`
}

type Attachment struct {
	Name string `json:"name"`
	Mime string `json:"mime"`
	Size int64  `json:"size"`
	Path string `json:"-"`
}

type Agent struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	Role      string `json:"role"`
	Harness   string `json:"harness"`
	Model     string `json:"model,omitempty"`
	Status    string `json:"status"`
	Task      string `json:"task,omitempty"`
	Session   string `json:"-"`
	Container string `json:"container"`
	CreatedAt int64  `json:"createdAt"`
	UpdatedAt int64  `json:"updatedAt"`
}

type AppRequest struct {
	Op      string `json:"op"`
	Since   int64  `json:"since,omitempty"`
	Text    string `json:"text,omitempty"`
	AgentID string `json:"agentId,omitempty"`
}

const (
	OpHello = "hello"
	OpSend  = "send"
	OpStop  = "stop"
)

type AppEvent struct {
	Type    string   `json:"type"`
	Message *Message `json:"message,omitempty"`
	Agent   *Agent   `json:"agent,omitempty"`
	Error   string   `json:"error,omitempty"`
}

const (
	EventReady   = "ready"
	EventMessage = "message"
	EventAgent   = "agent"
	EventError   = "error"
)

type BusRequest struct {
	Token   string `json:"token"`
	Op      string `json:"op"`
	Name    string `json:"name,omitempty"`
	Harness string `json:"harness,omitempty"`
	Model   string `json:"model,omitempty"`
	Task    string `json:"task,omitempty"`
	Kind    string `json:"kind,omitempty"`
	Text    string `json:"text,omitempty"`
	To      string `json:"to,omitempty"`
	Path    string `json:"path,omitempty"`
}

const (
	BusSpawn  = "spawn"
	BusReport = "report"
	BusSend   = "send"
	BusList   = "list"
	BusAttach = "attach"
)

type BusResponse struct {
	OK      bool    `json:"ok"`
	Error   string  `json:"error,omitempty"`
	AgentID string  `json:"agentId,omitempty"`
	Agents  []Agent `json:"agents,omitempty"`
}
