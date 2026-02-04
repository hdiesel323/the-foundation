-- =====================================================
-- OPENCLAW V2 MEMORY SCHEMA
-- =====================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
-- CREATE EXTENSION IF NOT EXISTS "vector";  -- Phase 2: semantic search

-- =====================================================
-- TRIGGER FUNCTION: auto-update updated_at
-- =====================================================
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- TABLE: preferences
-- =====================================================
CREATE TABLE preferences (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    agent_id VARCHAR(100) DEFAULT 'shared',
    category VARCHAR(100) NOT NULL,
    key VARCHAR(255) NOT NULL,
    value JSONB NOT NULL,
    version INTEGER DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(agent_id, category, key)
);

CREATE INDEX idx_preferences_category ON preferences(category);
CREATE INDEX idx_preferences_key ON preferences(key);
CREATE INDEX idx_preferences_agent ON preferences(agent_id);

CREATE TRIGGER preferences_updated_at BEFORE UPDATE ON preferences
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- =====================================================
-- TABLE: conversations
-- =====================================================
CREATE TABLE conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    agent_id VARCHAR(100) NOT NULL,
    title VARCHAR(500),
    context_summary TEXT,
    status VARCHAR(50) DEFAULT 'active',
    started_at TIMESTAMPTZ DEFAULT NOW(),
    last_activity_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX idx_conversations_status ON conversations(status);
CREATE INDEX idx_conversations_last_activity ON conversations(last_activity_at DESC);
CREATE INDEX idx_conversations_agent ON conversations(agent_id);

-- =====================================================
-- TABLE: messages
-- =====================================================
CREATE TABLE messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
    agent_id VARCHAR(100) NOT NULL,
    role VARCHAR(50) NOT NULL,
    content TEXT NOT NULL,
    tool_calls JSONB,
    tool_results JSONB,
    tokens_used INTEGER,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX idx_messages_conversation ON messages(conversation_id);
CREATE INDEX idx_messages_created ON messages(created_at DESC);

-- =====================================================
-- TABLE: tasks
-- =====================================================
CREATE TABLE tasks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    agent_id VARCHAR(100) NOT NULL,
    conversation_id UUID REFERENCES conversations(id),
    name VARCHAR(500) NOT NULL,
    description TEXT,
    status VARCHAR(50) DEFAULT 'pending',
    priority INTEGER DEFAULT 5,
    scheduled_at TIMESTAMPTZ,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    result JSONB,
    error_message TEXT,
    retry_count INTEGER DEFAULT 0,
    max_retries INTEGER DEFAULT 3,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb,
    acceptance_criteria JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX idx_tasks_status ON tasks(status);
CREATE INDEX idx_tasks_scheduled ON tasks(scheduled_at) WHERE scheduled_at IS NOT NULL;
CREATE INDEX idx_tasks_priority ON tasks(priority, created_at);

CREATE TRIGGER tasks_updated_at BEFORE UPDATE ON tasks
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- =====================================================
-- TABLE: facts (subject-predicate-object triples)
-- =====================================================
CREATE TABLE facts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    agent_id VARCHAR(100) DEFAULT 'shared',
    category VARCHAR(100) NOT NULL,
    subject VARCHAR(500) NOT NULL,
    predicate VARCHAR(255) NOT NULL,
    object TEXT NOT NULL,
    confidence DECIMAL(3,2) DEFAULT 1.0,
    source VARCHAR(255),
    valid_from TIMESTAMPTZ DEFAULT NOW(),
    valid_until TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX idx_facts_category ON facts(category);
CREATE INDEX idx_facts_subject ON facts(subject);
CREATE INDEX idx_facts_valid ON facts(valid_from, valid_until);
CREATE INDEX idx_facts_agent ON facts(agent_id);

CREATE TRIGGER facts_updated_at BEFORE UPDATE ON facts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- =====================================================
-- TABLE: entities (knowledge graph — contacts, projects, etc.)
-- =====================================================
CREATE TABLE entities (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    type VARCHAR(100) NOT NULL,
    name VARCHAR(500) NOT NULL,
    aliases TEXT[],
    attributes JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_entities_type ON entities(type);
CREATE INDEX idx_entities_name ON entities(name);
CREATE INDEX idx_entities_aliases ON entities USING GIN(aliases);

CREATE TRIGGER entities_updated_at BEFORE UPDATE ON entities
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- =====================================================
-- TABLE: relationships (between entities)
-- =====================================================
CREATE TABLE relationships (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    from_entity_id UUID REFERENCES entities(id) ON DELETE CASCADE,
    to_entity_id UUID REFERENCES entities(id) ON DELETE CASCADE,
    relationship_type VARCHAR(100) NOT NULL,
    attributes JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_relationships_from ON relationships(from_entity_id);
CREATE INDEX idx_relationships_to ON relationships(to_entity_id);
CREATE INDEX idx_relationships_type ON relationships(relationship_type);

-- =====================================================
-- TABLE: audit_log (action audit trail)
-- =====================================================
CREATE TABLE audit_log (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    action_type VARCHAR(100) NOT NULL,
    action_name VARCHAR(255) NOT NULL,
    input_summary TEXT,
    output_summary TEXT,
    status VARCHAR(50) NOT NULL,
    error_message TEXT,
    duration_ms INTEGER,
    conversation_id UUID REFERENCES conversations(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX idx_audit_action_type ON audit_log(action_type);
CREATE INDEX idx_audit_created ON audit_log(created_at DESC);
CREATE INDEX idx_audit_status ON audit_log(status);

-- =====================================================
-- TABLE: integrations (external service credentials)
-- =====================================================
CREATE TABLE integrations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) UNIQUE NOT NULL,
    type VARCHAR(50) NOT NULL,
    credentials_encrypted BYTEA,
    status VARCHAR(50) DEFAULT 'active',
    last_used_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX idx_integrations_name ON integrations(name);
CREATE INDEX idx_integrations_status ON integrations(status);

CREATE TRIGGER integrations_updated_at BEFORE UPDATE ON integrations
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- =====================================================
-- TABLE: metrics (internal system metrics)
-- =====================================================
CREATE TABLE metrics (
    id BIGSERIAL PRIMARY KEY,
    metric_name VARCHAR(255) NOT NULL,
    metric_value DECIMAL(20,6) NOT NULL,
    labels JSONB DEFAULT '{}'::jsonb,
    recorded_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_metrics_name ON metrics(metric_name);
CREATE INDEX idx_metrics_time ON metrics(recorded_at DESC);

-- =====================================================
-- TABLE: agents (multi-agent registry)
-- =====================================================
CREATE TABLE agents (
    id VARCHAR(100) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    role VARCHAR(100) NOT NULL,
    location VARCHAR(100),
    endpoint VARCHAR(500),
    status VARCHAR(50) DEFAULT 'offline',
    capabilities TEXT[],
    last_heartbeat TIMESTAMPTZ,
    registered_at TIMESTAMPTZ DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

-- =====================================================
-- TABLE: handoffs (agent-to-agent task handoffs)
-- =====================================================
CREATE TABLE handoffs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    from_agent VARCHAR(100) REFERENCES agents(id),
    to_agent VARCHAR(100) REFERENCES agents(id),
    context JSONB NOT NULL,
    status VARCHAR(50) DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    result JSONB
);

-- =====================================================
-- TABLE: foundry_tools (crystallized tools)
-- =====================================================
CREATE TABLE foundry_tools (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) UNIQUE NOT NULL,
    description TEXT,
    command TEXT NOT NULL,
    created_by VARCHAR(100) DEFAULT 'foundry',
    observed_from VARCHAR(100) REFERENCES agents(id),
    usage_count INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- =====================================================
-- TABLE: memory_sync_log (file-to-db sync tracking)
-- =====================================================
CREATE TABLE memory_sync_log (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    file_path VARCHAR(500) NOT NULL,
    sync_direction VARCHAR(20) NOT NULL,
    content_hash VARCHAR(64) NOT NULL,
    synced_at TIMESTAMPTZ DEFAULT NOW()
);

-- =====================================================
-- TABLE: critic_reviews (veto/approve decisions by critic agents)
-- =====================================================
CREATE TABLE critic_reviews (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    task_id UUID NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    critic_agent_id VARCHAR(100) NOT NULL REFERENCES agents(id),
    decision VARCHAR(20) NOT NULL CHECK (decision IN ('approve', 'veto')),
    reason TEXT,
    chain_name VARCHAR(100),
    layer_index INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX idx_critic_reviews_task ON critic_reviews(task_id);
CREATE INDEX idx_critic_reviews_agent ON critic_reviews(critic_agent_id);
CREATE INDEX idx_critic_reviews_decision ON critic_reviews(decision);

-- =====================================================
-- HELPER FUNCTION: estimate_tokens
-- Rough estimation: ~4 characters = 1 token
-- =====================================================
CREATE OR REPLACE FUNCTION estimate_tokens(text_content TEXT)
RETURNS INTEGER AS $$
BEGIN
    RETURN CEIL(LENGTH(COALESCE(text_content, '')) / 4.0);
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- TRIGGER: conversations_updated_at
-- conversations uses last_activity_at as its updated field
-- =====================================================
CREATE TRIGGER conversations_updated_at BEFORE UPDATE ON conversations
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- =====================================================
-- VIEW: session_context_size
-- Shows estimated token usage per active conversation
-- =====================================================
CREATE VIEW session_context_size AS
SELECT
    c.id AS conversation_id,
    c.title,
    COUNT(m.id) AS message_count,
    SUM(estimate_tokens(m.content)) AS estimated_tokens,
    CASE
        WHEN SUM(estimate_tokens(m.content)) > 150000 THEN 'CRITICAL'
        WHEN SUM(estimate_tokens(m.content)) > 100000 THEN 'WARNING'
        ELSE 'OK'
    END AS status
FROM conversations c
JOIN messages m ON m.conversation_id = c.id
WHERE c.status = 'active'
GROUP BY c.id, c.title;

-- =====================================================
-- FUNCTION: cleanup_old_context
-- Archives stale conversations, deletes very old ones
-- =====================================================
CREATE OR REPLACE FUNCTION cleanup_old_context(retention_days INTEGER DEFAULT 90)
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    UPDATE conversations
    SET status = 'archived'
    WHERE status = 'active'
    AND last_activity_at < NOW() - (retention_days || ' days')::INTERVAL;

    DELETE FROM conversations
    WHERE status = 'archived'
    AND last_activity_at < NOW() - ((retention_days * 2) || ' days')::INTERVAL;

    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- FUNCTION: auto_archive_bloated_conversations
-- Archives conversations exceeding CRITICAL token threshold
-- =====================================================
CREATE OR REPLACE FUNCTION auto_archive_bloated_conversations()
RETURNS INTEGER AS $$
DECLARE
    archived_count INTEGER;
BEGIN
    UPDATE conversations
    SET status = 'archived'
    WHERE id IN (
        SELECT conversation_id
        FROM session_context_size
        WHERE status = 'CRITICAL'
    );
    GET DIAGNOSTICS archived_count = ROW_COUNT;
    RETURN archived_count;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- Multi-Agent Orchestration: Workflows
-- ============================================================

CREATE TABLE IF NOT EXISTS workflows (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(500) NOT NULL,
    description TEXT,
    steps JSONB NOT NULL DEFAULT '[]'::jsonb,
    status VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'in_progress', 'completed', 'failed')),
    current_step INTEGER DEFAULT 0,
    result JSONB,
    error_message TEXT,
    created_by VARCHAR(100) REFERENCES agents(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_workflows_status ON workflows(status);
CREATE INDEX IF NOT EXISTS idx_workflows_created_by ON workflows(created_by);

CREATE TRIGGER workflows_updated_at
    BEFORE UPDATE ON workflows
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

-- ============================================================
-- Shared Agent Memory: Insights with TTL
-- ============================================================

CREATE TABLE IF NOT EXISTS insights (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    agent_id VARCHAR(100) NOT NULL REFERENCES agents(id),
    category VARCHAR(100) NOT NULL,
    content TEXT NOT NULL,
    confidence DECIMAL(3,2) DEFAULT 0.80,
    ttl_seconds INTEGER DEFAULT 3600,
    expires_at TIMESTAMPTZ NOT NULL DEFAULT NOW() + INTERVAL '1 hour',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_insights_agent ON insights(agent_id);
CREATE INDEX IF NOT EXISTS idx_insights_category ON insights(category);
CREATE INDEX IF NOT EXISTS idx_insights_expires_at ON insights(expires_at);
CREATE INDEX IF NOT EXISTS idx_insights_confidence ON insights(confidence DESC);

-- ============================================================
-- Event Feed: Activities
-- ============================================================

CREATE TABLE IF NOT EXISTS activities (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_type VARCHAR(50) NOT NULL
        CHECK (event_type IN (
            'message', 'task_created', 'task_completed', 'task_failed',
            'agent_online', 'agent_offline',
            'project_update', 'alert', 'handoff', 'patrol'
        )),
    agent_id VARCHAR(100) REFERENCES agents(id),
    division VARCHAR(50),
    details JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_activities_event_type ON activities(event_type);
CREATE INDEX IF NOT EXISTS idx_activities_agent ON activities(agent_id);
CREATE INDEX IF NOT EXISTS idx_activities_division ON activities(division);
CREATE INDEX IF NOT EXISTS idx_activities_created_at ON activities(created_at DESC);

-- ============================================================
-- Project Management with Heat Scoring
-- ============================================================

CREATE TABLE IF NOT EXISTS projects (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(500) NOT NULL,
    description TEXT,
    heat INTEGER NOT NULL DEFAULT 0 CHECK (heat >= 0 AND heat <= 10),
    tier VARCHAR(20) DEFAULT 'standard',
    status VARCHAR(20) NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'paused', 'completed', 'archived')),
    division VARCHAR(50),
    assigned_agent VARCHAR(100) REFERENCES agents(id),
    revenue BOOLEAN DEFAULT false,
    last_active TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_projects_heat ON projects(heat DESC);
CREATE INDEX IF NOT EXISTS idx_projects_status ON projects(status);
CREATE INDEX IF NOT EXISTS idx_projects_division ON projects(division);
CREATE INDEX IF NOT EXISTS idx_projects_assigned ON projects(assigned_agent);

CREATE TRIGGER projects_updated_at
    BEFORE UPDATE ON projects
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

-- ============================================================
-- Routing Decisions (Outcome Tracker)
-- ============================================================

CREATE TABLE IF NOT EXISTS routing_decisions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    message_id UUID,
    agent_id VARCHAR(100) NOT NULL REFERENCES agents(id),
    score DECIMAL(10,6) NOT NULL DEFAULT 0,
    confidence DECIMAL(3,2) DEFAULT 0.50,
    outcome VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (outcome IN ('success', 'failure', 'pending')),
    response_time_ms INTEGER,
    multiplier_at_time DECIMAL(4,2) DEFAULT 1.00,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_routing_decisions_agent ON routing_decisions(agent_id);
CREATE INDEX IF NOT EXISTS idx_routing_decisions_created ON routing_decisions(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_routing_decisions_outcome ON routing_decisions(outcome);
