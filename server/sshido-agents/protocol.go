package main

const (
	KindUser       = "user"
	KindReply      = "reply"
	KindProgress   = "progress"
	KindDone       = "done"
	KindNeedsInput = "needs_input"
	KindSignIn     = "sign_in"
	KindError      = "error"
	KindFile       = "file"
)

const (
	RoleOrchestrator = "orchestrator"
	RoleWorker       = "worker"
	RoleMember       = "member"
)

type Chat struct {
	ID        string `json:"id"`
	Title     string `json:"title"`
	CreatedAt int64  `json:"createdAt"`
}

type Record struct {
	Goal         string
	WorkStatus   string
	Verification string
	Verdict      string
	VerdictNote  string
}

const (
	WorkInProgress = "in_progress"
	WorkBlocked    = "blocked"
	WorkDone       = "done"
)

const (
	VerdictPass = "pass"
	VerdictFail = "fail"
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
	ChatID     string      `json:"chatId"`
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
	ID           string `json:"id"`
	ChatID       string `json:"chatId"`
	Name         string `json:"name"`
	Role         string `json:"role"`
	Harness      string `json:"harness"`
	Model        string `json:"model,omitempty"`
	Status       string `json:"status"`
	Task         string `json:"task,omitempty"`
	Goal         string `json:"goal,omitempty"`
	WorkStatus   string `json:"workStatus,omitempty"`
	Verification string `json:"verification,omitempty"`
	Verdict      string `json:"verdict,omitempty"`
	VerdictNote  string `json:"verdictNote,omitempty"`
	Session      string `json:"-"`
	Mounts       string `json:"-"`
	Briefed      string `json:"-"`
	Container    string `json:"container"`
	CreatedAt    int64  `json:"createdAt"`
	UpdatedAt    int64  `json:"updatedAt"`
}

type AppRequest struct {
	Op      string `json:"op"`
	Since   int64  `json:"since,omitempty"`
	ChatID  string `json:"chatId,omitempty"`
	Text    string `json:"text,omitempty"`
	AgentID string `json:"agentId,omitempty"`
	Title   string `json:"title,omitempty"`
}

const (
	OpHello      = "hello"
	OpSend       = "send"
	OpStop       = "stop"
	OpCreateChat = "createChat"
	OpDeleteChat = "deleteChat"
	OpSignedIn   = "signedIn"
)

type AppEvent struct {
	Type    string   `json:"type"`
	Message *Message `json:"message,omitempty"`
	Agent   *Agent   `json:"agent,omitempty"`
	Chat    *Chat    `json:"chat,omitempty"`
	ChatID  string   `json:"chatId,omitempty"`
	Error   string   `json:"error,omitempty"`
}

const (
	EventReady       = "ready"
	EventMessage     = "message"
	EventAgent       = "agent"
	EventChat        = "chat"
	EventChatRemoved = "chatRemoved"
	EventError       = "error"
)

type BusRequest struct {
	Token   string `json:"token"`
	Op      string `json:"op"`
	Name    string `json:"name,omitempty"`
	Harness string `json:"harness,omitempty"`
	Model   string `json:"model,omitempty"`
	Task    string `json:"task,omitempty"`
	Goal    string `json:"goal,omitempty"`
	Kind    string `json:"kind,omitempty"`
	Text    string `json:"text,omitempty"`
	To      string `json:"to,omitempty"`
	Path    string `json:"path,omitempty"`
}

const (
	BusSpawn   = "spawn"
	BusReport  = "report"
	BusSend    = "send"
	BusList    = "list"
	BusAttach  = "attach"
	BusStop    = "stop"
	BusGoal    = "goal"
	BusStatus  = "status"
	BusVerify  = "verify"
	BusLog     = "log"
	BusVerdict = "verdict"
	BusRecord  = "record"
)

type BusResponse struct {
	OK      bool    `json:"ok"`
	Error   string  `json:"error,omitempty"`
	AgentID string  `json:"agentId,omitempty"`
	Agents  []Agent `json:"agents,omitempty"`
	Text    string  `json:"text,omitempty"`
}
