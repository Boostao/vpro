package main

import (
	"container/list"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"strings"
	"sync"
)

// PreviewCacheStats summarizes bounded LRU preview cache utilization.
type PreviewCacheStats struct {
	MaxBytes  int64 `json:"maxBytes"`
	UsedBytes int64 `json:"usedBytes"`
	Entries   int   `json:"entries"`
	Hits      int64 `json:"hits"`
	Misses    int64 `json:"misses"`
	Evictions int64 `json:"evictions"`
}

type previewCacheEntry struct {
	key  string
	body []byte
	etag string
	size int64
}

// PreviewCache is a thread-safe byte-bounded LRU cache for deterministic read-only
// RPC responses, keyed by (generation, service, method, canonicalArgsHash).
type PreviewCache struct {
	mu        sync.Mutex
	maxBytes  int64
	usedBytes int64
	lru       *list.List
	entries   map[string]*list.Element
	hits      int64
	misses    int64
	evictions int64
}

func NewPreviewCache(maxMB int) *PreviewCache {
	var maxBytes int64
	if maxMB > 0 {
		maxBytes = int64(maxMB) * 1024 * 1024
	}
	return &PreviewCache{
		maxBytes: maxBytes,
		lru:      list.New(),
		entries:  make(map[string]*list.Element),
	}
}

func BuildPreviewCacheKey(generation, service, method string, rawArgs []json.RawMessage) string {
	h := sha256.New()
	_, _ = h.Write([]byte(generation))
	_, _ = h.Write([]byte{0})
	_, _ = h.Write([]byte(service))
	_, _ = h.Write([]byte{0})
	_, _ = h.Write([]byte(method))
	_, _ = h.Write([]byte{0})
	for _, arg := range rawArgs {
		// Normalize whitespace for canonical hashing if valid JSON.
		var normalized any
		if err := json.Unmarshal(arg, &normalized); err == nil {
			if canon, err := json.Marshal(normalized); err == nil {
				_, _ = h.Write(canon)
				_, _ = h.Write([]byte{0})
				continue
			}
		}
		_, _ = h.Write(arg)
		_, _ = h.Write([]byte{0})
	}
	return hex.EncodeToString(h.Sum(nil))
}

func computeResponseETag(body []byte) string {
	sum := sha256.Sum256(body)
	return `"` + hex.EncodeToString(sum[:16]) + `"`
}

func (c *PreviewCache) Get(key string) (body []byte, etag string, ok bool) {
	if c == nil || c.maxBytes <= 0 {
		return nil, "", false
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	elem, exists := c.entries[key]
	if !exists {
		c.misses++
		return nil, "", false
	}
	c.lru.MoveToFront(elem)
	c.hits++
	item := elem.Value.(*previewCacheEntry)
	copied := make([]byte, len(item.body))
	copy(copied, item.body)
	return copied, item.etag, true
}

func (c *PreviewCache) Set(key string, body []byte) string {
	etag := computeResponseETag(body)
	if c == nil || c.maxBytes <= 0 {
		return etag
	}
	entrySize := int64(len(body)) + int64(len(key)) + int64(len(etag)) + 64
	if entrySize > c.maxBytes {
		return etag
	}

	copied := make([]byte, len(body))
	copy(copied, body)

	c.mu.Lock()
	defer c.mu.Unlock()

	if existing, ok := c.entries[key]; ok {
		old := existing.Value.(*previewCacheEntry)
		c.usedBytes -= old.size
		old.body = copied
		old.etag = etag
		old.size = entrySize
		c.usedBytes += entrySize
		c.lru.MoveToFront(existing)
	} else {
		item := &previewCacheEntry{
			key:  key,
			body: copied,
			etag: etag,
			size: entrySize,
		}
		elem := c.lru.PushFront(item)
		c.entries[key] = elem
		c.usedBytes += entrySize
	}

	for c.usedBytes > c.maxBytes && c.lru.Len() > 0 {
		oldest := c.lru.Back()
		if oldest == nil {
			break
		}
		c.lru.Remove(oldest)
		evicted := oldest.Value.(*previewCacheEntry)
		delete(c.entries, evicted.key)
		c.usedBytes -= evicted.size
		c.evictions++
	}
	return etag
}

func (c *PreviewCache) Clear() {
	if c == nil {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	c.lru.Init()
	c.entries = make(map[string]*list.Element)
	c.usedBytes = 0
}

func (c *PreviewCache) Stats() PreviewCacheStats {
	if c == nil {
		return PreviewCacheStats{}
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	return PreviewCacheStats{
		MaxBytes:  c.maxBytes,
		UsedBytes: c.usedBytes,
		Entries:   len(c.entries),
		Hits:      c.hits,
		Misses:    c.misses,
		Evictions: c.evictions,
	}
}

func etagMatches(ifNoneMatch, etag string) bool {
	if strings.TrimSpace(ifNoneMatch) == "" || strings.TrimSpace(etag) == "" {
		return false
	}
	for _, candidate := range strings.Split(ifNoneMatch, ",") {
		trimmed := strings.TrimSpace(candidate)
		if trimmed == "*" || trimmed == etag || strings.TrimPrefix(trimmed, "W/") == etag {
			return true
		}
	}
	return false
}
