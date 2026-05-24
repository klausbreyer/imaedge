const DB_NAME = "imaedge-upload-queue"
const DB_VERSION = 1
const STORE = "files"

function openDb() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION)
    request.onupgradeneeded = () => request.result.createObjectStore(STORE, {keyPath: "id"})
    request.onsuccess = () => resolve(request.result)
    request.onerror = () => reject(request.error)
  })
}

function tx(db, mode, callback) {
  return new Promise((resolve, reject) => {
    const transaction = db.transaction(STORE, mode)
    const store = transaction.objectStore(STORE)
    const result = callback(store)
    transaction.oncomplete = () => resolve(result)
    transaction.onerror = () => reject(transaction.error)
  })
}

async function putRecord(record) {
  const db = await openDb()
  return tx(db, "readwrite", store => store.put(record))
}

async function deleteRecord(id) {
  const db = await openDb()
  return tx(db, "readwrite", store => store.delete(id))
}

async function allRecords(collectionId) {
  const db = await openDb()

  return new Promise((resolve, reject) => {
    const records = []
    const transaction = db.transaction(STORE, "readonly")
    const request = transaction.objectStore(STORE).openCursor()

    request.onsuccess = () => {
      const cursor = request.result
      if (!cursor) return
      if (cursor.value.collectionId === collectionId) records.push(cursor.value)
      cursor.continue()
    }

    transaction.oncomplete = () => resolve(records)
    transaction.onerror = () => reject(transaction.error)
  })
}

async function sha256(file) {
  const buffer = await file.arrayBuffer()
  const hash = await crypto.subtle.digest("SHA-256", buffer)
  return [...new Uint8Array(hash)].map(byte => byte.toString(16).padStart(2, "0")).join("")
}

function contributorId() {
  const key = "imaedge:contributor-id"
  const current = localStorage.getItem(key)
  if (current) return current

  const adjectives = ["quiet", "golden", "clear", "bright", "steady", "brave", "silver", "warm", "wild", "fresh"]
  const nouns = ["harbor", "maple", "summit", "lantern", "river", "orbit", "signal", "meadow", "anchor", "atlas"]
  const random = array => array[Math.floor(Math.random() * array.length)]
  const value = `${random(adjectives)}-${random(nouns)}`
  localStorage.setItem(key, value)
  return value
}

function formatBytes(bytes) {
  if (!Number.isFinite(bytes)) return "unknown"
  const units = ["B", "KB", "MB", "GB"]
  let value = bytes
  let unit = 0

  while (value >= 1024 && unit < units.length - 1) {
    value = value / 1024
    unit += 1
  }

  return `${value.toFixed(unit === 0 ? 0 : 1)} ${units[unit]}`
}

function nowLine(message) {
  return `${new Date().toISOString()} ${message}`
}

export const UploadQueue = {
  async mounted() {
    this.collectionId = this.el.dataset.collectionId
    this.csrf = document.querySelector("meta[name='csrf-token']").content
    this.input = this.el.querySelector("#image-picker")
    this.queueEl = this.el.querySelector("#client-queue")
    this.storageEl = this.el.querySelector("#storage-estimate")
    this.concurrencyEl = this.el.querySelector("#upload-concurrency")
    this.logEl = this.el.querySelector("#debug-log-output")
    this.copyLogButton = this.el.querySelector("#copy-debug-log")
    this.clearLogButton = this.el.querySelector("#clear-debug-log")
    this.records = []
    this.active = 0
    this.poll = null

    this.input.addEventListener("change", event => this.addFiles([...event.target.files]))
    this.concurrencyEl.addEventListener("change", () => this.pump())
    this.copyLogButton.addEventListener("click", () => navigator.clipboard.writeText(this.logEl.textContent))
    this.clearLogButton.addEventListener("click", () => this.setLog(""))

    this.records = (await allRecords(this.collectionId)).map(record => ({
      ...record,
      status: ["uploading", "checking duplicate", "finalizing", "local storage"].includes(record.status) ? "queued" : record.status
    }))
    this.render()
    this.updateStorageEstimate()
    this.log(`queue loaded with ${this.records.length} local record(s)`)
    this.pump()

    this.poll = window.setInterval(() => this.refreshServerStates(), 15000)
  },

  destroyed() {
    if (this.poll) window.clearInterval(this.poll)
  },

  async addFiles(files) {
    for (const file of files) {
      if (!["image/jpeg", "image/png", "image/webp"].includes(file.type)) {
        this.log(`rejected unsupported file ${file.name} (${file.type || "unknown"})`)
        continue
      }

      const id = crypto.randomUUID()
      const record = {
        id,
        collectionId: this.collectionId,
        name: file.name,
        type: file.type,
        size: file.size,
        status: "local storage",
        progress: 0,
        speed: "",
        error: "",
        contributorId: contributorId(),
        timezoneOffsetMinutes: -new Date().getTimezoneOffset(),
        createdAt: new Date().toISOString(),
        file
      }

      this.records.push(record)
      this.render()

      try {
        const hash = await sha256(file)
        if (this.records.some(item => item.id !== id && item.sha256 === hash)) {
          record.status = "duplicate local"
          record.error = "Same file is already in this local queue"
          this.log(`local duplicate skipped ${file.name}`)
          this.render()
          continue
        }

        record.sha256 = hash
        record.status = "queued"
        await putRecord(record)
        this.log(`stored ${file.name} (${formatBytes(file.size)}) hash=${hash}`)
      } catch (error) {
        record.status = "failed"
        record.error = String(error)
        this.log(`failed to store ${file.name}: ${record.error}`)
      }

      this.render()
      this.updateStorageEstimate()
    }

    this.input.value = ""
    this.pump()
  },

  async pump() {
    const limit = Number(this.concurrencyEl.value || 1)

    while (this.active < limit) {
      const record = this.records.find(item => ["queued", "failed upload"].includes(item.status))
      if (!record) return

      this.active += 1
      this.upload(record).finally(() => {
        this.active -= 1
        this.pump()
      })
    }
  },

  async upload(record) {
    try {
      record.status = "checking duplicate"
      this.render()

      if (!record.sessionId) {
        const session = await this.createSession(record)
        if (session.duplicate) {
          record.status = "already present"
          record.progress = 100
          await deleteRecord(record.id)
          this.removeSoon(record)
          this.log(`server duplicate ${record.name}`)
          return
        }

        record.sessionId = session.id
        record.chunkSize = session.chunk_size
        record.totalChunks = session.total_chunks
        await putRecord(record)
      }

      const status = await this.fetchStatus(record)
      if (["processing", "done"].includes(status.status)) {
        record.status = status.status === "done" ? "complete" : "processing"
        record.progress = 100
        await deleteRecord(record.id)
        this.log(`server already accepted ${record.name}, local copy released`)
        this.removeSoon(record)
        this.updateStorageEstimate()
        return
      }

      record.status = "uploading"
      await this.uploadMissingChunks(record, status.missing_chunks)

      record.status = "finalizing"
      this.render()
      await this.finalize(record)

      record.status = "processing"
      record.progress = 100
      await deleteRecord(record.id)
      this.log(`finalized ${record.name}, local copy released`)
      this.removeSoon(record)
      this.updateStorageEstimate()
    } catch (error) {
      record.status = "failed upload"
      record.error = String(error)
      await putRecord(record).catch(() => {})
      this.log(`upload failed ${record.name}: ${record.error}`)
      this.render()
    }
  },

  async createSession(record) {
    const response = await this.jsonFetch(`/i/${this.collectionId}/uploads`, {
      method: "POST",
      body: JSON.stringify({
        filename: record.name,
        mime: record.type,
        byte_size: record.size,
        sha256: record.sha256,
        contributor_id: record.contributorId,
        timezone_offset_minutes: record.timezoneOffsetMinutes
      })
    })

    this.log(`session response ${record.name}: ${JSON.stringify(response)}`)
    return response
  },

  async fetchStatus(record) {
    return this.jsonFetch(`/i/${this.collectionId}/uploads/${record.sessionId}`)
  },

  async uploadMissingChunks(record, missingChunks) {
    const started = performance.now()
    let uploaded = (record.totalChunks - missingChunks.length) * record.chunkSize

    for (const index of missingChunks) {
      const start = index * record.chunkSize
      const end = Math.min(start + record.chunkSize, record.size)
      const chunk = record.file.slice(start, end)

      await fetch(`/i/${this.collectionId}/uploads/${record.sessionId}/chunks/${index}`, {
        method: "PUT",
        headers: {"x-csrf-token": this.csrf, "content-type": "application/octet-stream"},
        body: chunk
      }).then(async response => {
        if (!response.ok) throw new Error(`chunk ${index} failed HTTP ${response.status}: ${await response.text()}`)
      })

      uploaded += chunk.size
      record.progress = Math.min(99, Math.round((uploaded / record.size) * 100))
      const seconds = Math.max((performance.now() - started) / 1000, 0.1)
      record.speed = `${formatBytes(uploaded / seconds)}/s`
      this.render()
    }
  },

  async finalize(record) {
    return this.jsonFetch(`/i/${this.collectionId}/uploads/${record.sessionId}/finalize`, {method: "POST"})
  },

  async refreshServerStates() {
    for (const record of this.records.filter(item => item.sessionId && item.status !== "processing")) {
      try {
        const status = await this.fetchStatus(record)
        if (status.status === "failed") {
          record.status = "failed processing"
          record.error = status.error_message || "Processing failed"
          this.render()
        }
      } catch (error) {
        this.log(`status poll failed for ${record.name}: ${String(error)}`)
      }
    }
  },

  async jsonFetch(url, options = {}) {
    const response = await fetch(url, {
      ...options,
      headers: {
        "accept": "application/json",
        "content-type": "application/json",
        "x-csrf-token": this.csrf,
        ...(options.headers || {})
      }
    })

    const text = await response.text()
    const body = text ? parseJsonOrText(text) : {}
    if (!response.ok) throw new Error(`HTTP ${response.status}: ${typeof body === "string" ? body : JSON.stringify(body)}`)
    return body
  },

  removeSoon(record) {
    window.setTimeout(() => {
      this.records = this.records.filter(item => item.id !== record.id)
      this.render()
    }, 7000)
  },

  async updateStorageEstimate() {
    if (!navigator.storage || !navigator.storage.estimate) {
      this.storageEl.textContent = "Storage estimate unavailable"
      return
    }

    const estimate = await navigator.storage.estimate()
    const available = estimate.quota && estimate.usage ? estimate.quota - estimate.usage : null
    this.storageEl.textContent = `Local storage: ${formatBytes(estimate.usage)} used, ${formatBytes(available)} free estimate`
  },

  render() {
    if (!this.records.length) {
      this.queueEl.innerHTML = `<p class="empty-state">No local uploads waiting.</p>`
      return
    }

    this.queueEl.innerHTML = this.records.map(record => `
      <article class="queue-row">
        <div>
          <strong>${escapeHtml(record.name)}</strong>
          <span>${escapeHtml(record.status)} ${record.speed ? `- ${escapeHtml(record.speed)}` : ""}</span>
          ${record.error ? `<code>${escapeHtml(record.error)}</code>` : ""}
        </div>
        <progress max="100" value="${record.progress || 0}"></progress>
      </article>
    `).join("")
  },

  log(message) {
    const key = `imaedge:log:${this.collectionId}`
    const next = `${localStorage.getItem(key) || ""}${nowLine(message)}\n`.split("\n").slice(-220).join("\n")
    this.setLog(next)
  },

  setLog(value) {
    const key = `imaedge:log:${this.collectionId}`
    localStorage.setItem(key, value)
    this.logEl.textContent = value
  }
}

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, char => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    "\"": "&quot;",
    "'": "&#039;"
  }[char]))
}

function parseJsonOrText(text) {
  try {
    return JSON.parse(text)
  } catch (_error) {
    return text
  }
}
