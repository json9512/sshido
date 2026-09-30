package main

import (
	"fmt"
	"strings"
	"unicode/utf8"
)

const orchestratorBrief = `You are the orchestrator in sshido agent mode. The person talks to you from a
phone chat. You run in your own container; the project files are in /workspace,
shared with every agent you start.

Split the person's request into tasks and hand them to worker agents with the
agentctl command. Do small things yourself; hand off work that takes real time
or can run in parallel.

  agentctl spawn --name <short-name> --task "<self-contained task>" [--harness claude|codex|gemini|grok|local] [--model <model>]
      Start a worker in its own container. It starts with no context but the
      task text, so include everything it needs. Prints the worker id.
  agentctl send --to <worker-id> "<message>"
      Give a running worker a follow-up instruction.
  agentctl list
      Show every agent and whether it is working or idle.
  agentctl report --progress "<one line>"
      Tell the person about progress while you keep working.

After you start workers, end your turn with one short line saying what you
started. Do not wait for them or poll agentctl list: when a worker finishes,
you get its final report as a new message. When the whole request is done,
answer the person briefly: what was done, where it is, and anything they must
decide. Your reply to each message is shown in the chat.`

const computerBrief = `What you can use in your container:
- The internet: you have network access, including the web.
- A real web browser through the agent-browser command. One browser session
  stays open between commands:
    agent-browser open <url>             open a page
    agent-browser snapshot               list what is on the page, with refs like @e3
    agent-browser click @e3              click an element by ref
    agent-browser fill @e5 "<text>"      type into a field by ref
    agent-browser get title              the page title
    agent-browser screenshot /workspace/<name>.png
    agent-browser read <url>             fetch a page's text without opening the browser
    agent-browser close                  close the browser
  After open or click, take a snapshot before choosing the next ref.
- Files: read, create, edit and delete files anywhere under /workspace with
  your own tools or the shell. Save screenshots, downloads and results there.
- Showing things: the person sees the chat on a phone, not your files. To show
  a picture, video or any file in the chat, run
    agentctl attach /workspace/<file> --caption "<what it is>"
  Attach screenshots and results instead of only mentioning their paths.
Do not tell the person you cannot browse or cannot reach the internet.`

const workerBrief = `You are a worker agent in sshido agent mode, named %q. You run in your own
container; the project files are in /workspace, shared with the other agents.
The orchestrator gave you the task below. Do it completely.

  agentctl report --progress "<one line>"      tell the person about progress
  agentctl report --needs-input "<question>"   ask the person something you cannot decide

Your final reply is your report to the orchestrator: what you did, what you
changed, and anything left open.`

const memberBrief = `You are %q, a member of a group chat in sshido agent mode. The person and
these members share one chat:
%s
A picker chooses who speaks next, one member at a time. When it is your turn you
get the chat messages you have not seen yet. Do the work your part needs (you
have your own container; /workspace is shared with the other members), then
reply with your contribution. Name another member when you want them to act
next. Keep replies short: the person reads them on a phone.

  agentctl report --progress "<one line>"      tell the person about progress
  agentctl report --needs-input "<question>"   ask the person something you cannot decide`

func hostDirsBrief(dirs []HostDir) string {
	if len(dirs) == 0 {
		return ""
	}
	lines := make([]string, 0, len(dirs))
	for _, d := range dirs {
		lines = append(lines, fmt.Sprintf("    %s   (the person's %s)", d.Target(), d.Source))
	}
	return "\n- Host folders: the person's computer shares these folders with you, read-only:\n" +
		strings.Join(lines, "\n") +
		"\n  Read them freely. To change or build something from them, copy it into\n" +
		"  /workspace and work on the copy; the host folders cannot be written."
}

func hostDirsChanged(dirs []HostDir) string {
	if len(dirs) == 0 {
		return "Note: the person stopped sharing host folders. Nothing is under /host any more."
	}
	return "Note: the person changed the shared host folders. What you can use now:" + hostDirsBrief(dirs)
}

func memberRoster(members []Agent) string {
	lines := make([]string, 0, len(members))
	for _, m := range members {
		lines = append(lines, fmt.Sprintf("  - %s (%s)", m.Name, m.Harness))
	}
	return strings.Join(lines, "\n")
}

func firstTurnPrompt(a Agent, text string, dirs []HostDir, members []Agent) string {
	computer := computerBrief + hostDirsBrief(dirs)
	switch a.Role {
	case RoleOrchestrator:
		return orchestratorBrief + "\n\n" + computer + "\n\n---\n\n" + text
	case RoleMember:
		return fmt.Sprintf(memberBrief, a.Name, memberRoster(members)) + "\n\n" + computer + "\n\n---\n\n" + text
	}
	return fmt.Sprintf(workerBrief, a.Name) + "\n\n" + computer + "\n\n---\n\nTask:\n" + text
}

func renderMessage(m Message) string {
	switch m.Kind {
	case KindFile:
		name := ""
		if m.Attachment != nil {
			name = m.Attachment.Name
		}
		return fmt.Sprintf("%s attached %s: %s", m.Author, name, m.Text)
	case KindProgress:
		return fmt.Sprintf("%s (progress): %s", m.Author, m.Text)
	case KindNeedsInput:
		return fmt.Sprintf("%s (question for the person): %s", m.Author, m.Text)
	case KindError:
		return fmt.Sprintf("%s (error): %s", m.Author, m.Text)
	}
	return fmt.Sprintf("%s: %s", m.Author, m.Text)
}

func renderTranscript(messages []Message) string {
	lines := make([]string, 0, len(messages))
	for _, m := range messages {
		lines = append(lines, renderMessage(m))
	}
	return strings.Join(lines, "\n\n")
}

func memberTurnPrompt(unseen []Message) string {
	if len(unseen) == 0 {
		return "Nothing new was said since your last turn. Continue your part, or say briefly that you are done."
	}
	return "New messages in the chat since your last turn:\n\n" + renderTranscript(unseen) + "\n\nIt is your turn to speak."
}

const pickerHistoryChars = 24000

func repliesSinceUser(messages []Message) []string {
	names := []string{}
	for _, m := range messages {
		if m.Kind == KindUser {
			names = []string{}
			continue
		}
		if m.Kind != KindReply {
			continue
		}
		names = append(names, m.Author)
	}
	return names
}

func clipHistory(transcript string) string {
	if len(transcript) <= pickerHistoryChars {
		return transcript
	}
	return "[earlier messages removed]\n" + transcript[runeStart(transcript, len(transcript)-pickerHistoryChars):]
}

func runeStart(s string, i int) int {
	if i >= len(s) || utf8.RuneStart(s[i]) {
		return i
	}
	return runeStart(s, i+1)
}

func lastUserText(messages []Message) string {
	text := ""
	for _, m := range messages {
		if m.Kind != KindUser {
			continue
		}
		text = m.Text
	}
	return text
}

func repliedLine(replied []string) string {
	if len(replied) == 0 {
		return "No member has replied to it yet."
	}
	return "Members who replied to it, in order: " + strings.Join(replied, ", ") +
		". The last reply was from " + replied[len(replied)-1] + "."
}

func pickerState(chat Chat, members []Agent, messages []Message) string {
	return fmt.Sprintf("Group chat %q. Members:\n%s\n\nChat so far, oldest first:\n\n%s\n\n---\nThe person's latest message: %q\n%s",
		chat.Title, memberRoster(members), clipHistory(renderTranscript(messages)), lastUserText(messages),
		repliedLine(repliesSinceUser(messages)))
}

func pickerQuestion(handBack bool) string {
	if handBack {
		return "Who should speak next in this group chat, or should it stop?"
	}
	return "Who should speak next in this group chat?"
}

func pickerOptions(members []Agent, handBack bool) []PickOption {
	options := make([]PickOption, 0, len(members)+1)
	for _, m := range members {
		options = append(options, PickOption{Name: m.Name, Description: m.Name + " still has something to add that the person's latest message asks for"})
	}
	if !handBack {
		return options
	}
	return append(options, PickOption{
		Name:        "stop",
		Description: "the person's latest message has been answered, or only the person can decide what comes next; hand the chat back to the person",
	})
}

func workerFinishedPrompt(name, id, report string) string {
	return fmt.Sprintf("Worker %q (%s) finished its turn. Its report:\n\n%s\n\n"+
		"Continue the plan. If the person's request is complete, reply to them.", name, id, report)
}

func workerFailedPrompt(name, id, failure string) string {
	return fmt.Sprintf("Worker %q (%s) failed: %s\n\nDecide whether to retry, reassign, or tell the person.", name, id, failure)
}
