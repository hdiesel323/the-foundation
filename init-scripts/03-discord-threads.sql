-- =====================================================
-- MIGRATION: Discord Thread Linking for Tasks
-- =====================================================
-- Implements the task-to-Discord-thread architecture:
--   Task created → Dashboard entry + Discord thread (linked)
--   Agents work in Discord thread
--   Task completed → lead agent posts summary → archive
-- =====================================================

-- Add Discord thread columns to tasks table
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS discord_thread_id VARCHAR(100);
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS discord_channel_id VARCHAR(100);
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS discord_message_url TEXT;
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS lead_agent VARCHAR(100);
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS participating_agents TEXT[] DEFAULT '{}';
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS completion_summary TEXT;
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_tasks_discord_thread ON tasks(discord_thread_id) WHERE discord_thread_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_tasks_lead_agent ON tasks(lead_agent) WHERE lead_agent IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_tasks_archived ON tasks(archived_at) WHERE archived_at IS NOT NULL;

-- =====================================================
-- TABLE: discord_thread_messages
-- Tracks agent messages within task threads
-- =====================================================
CREATE TABLE IF NOT EXISTS discord_thread_messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    task_id UUID NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    discord_thread_id VARCHAR(100) NOT NULL,
    discord_message_id VARCHAR(100),
    agent_id VARCHAR(100) REFERENCES agents(id),
    message_type VARCHAR(50) DEFAULT 'work_update',
    -- work_update, question, handoff, status, completion_summary, veto, approval
    content TEXT NOT NULL,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_thread_messages_task ON discord_thread_messages(task_id);
CREATE INDEX IF NOT EXISTS idx_thread_messages_thread ON discord_thread_messages(discord_thread_id);
CREATE INDEX IF NOT EXISTS idx_thread_messages_agent ON discord_thread_messages(agent_id);

-- =====================================================
-- TABLE: task_archive
-- Completed tasks moved here after archival period
-- =====================================================
CREATE TABLE IF NOT EXISTS task_archive (
    id UUID PRIMARY KEY,
    original_task_id UUID NOT NULL,
    agent_id VARCHAR(100) NOT NULL,
    lead_agent VARCHAR(100),
    name VARCHAR(500) NOT NULL,
    description TEXT,
    status VARCHAR(50),
    priority INTEGER,
    result JSONB,
    completion_summary TEXT,
    discord_thread_id VARCHAR(100),
    discord_channel_id VARCHAR(100),
    participating_agents TEXT[] DEFAULT '{}',
    thread_message_count INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    archived_at TIMESTAMPTZ DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_task_archive_agent ON task_archive(agent_id);
CREATE INDEX IF NOT EXISTS idx_task_archive_lead ON task_archive(lead_agent);
CREATE INDEX IF NOT EXISTS idx_task_archive_completed ON task_archive(completed_at);
