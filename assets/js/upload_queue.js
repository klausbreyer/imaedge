const DB_NAME = "imaedge-upload-queue"
const DB_VERSION = 1
const STORE = "files"
const CONTROL_REQUEST_TIMEOUT_MS = 25_000
const FINALIZE_REQUEST_TIMEOUT_MS = 120_000
const CHUNK_REQUEST_TIMEOUT_MS = 60_000

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

  if (!globalThis.crypto || !globalThis.crypto.subtle) {
    return sha256Bytes(new Uint8Array(buffer))
  }

  const hash = await crypto.subtle.digest("SHA-256", buffer)
  return [...new Uint8Array(hash)].map(byte => byte.toString(16).padStart(2, "0")).join("")
}

function sha256Bytes(bytes) {
  const words = new Uint32Array(64)
  const bitLength = bytes.length * 8
  const paddedLength = Math.ceil((bytes.length + 1 + 8) / 64) * 64
  const padded = new Uint8Array(paddedLength)
  const view = new DataView(padded.buffer)
  let h0 = 0x6a09e667
  let h1 = 0xbb67ae85
  let h2 = 0x3c6ef372
  let h3 = 0xa54ff53a
  let h4 = 0x510e527f
  let h5 = 0x9b05688c
  let h6 = 0x1f83d9ab
  let h7 = 0x5be0cd19

  padded.set(bytes)
  padded[bytes.length] = 0x80
  view.setUint32(paddedLength - 8, Math.floor(bitLength / 0x100000000))
  view.setUint32(paddedLength - 4, bitLength >>> 0)

  for (let offset = 0; offset < paddedLength; offset += 64) {
    for (let index = 0; index < 16; index += 1) {
      words[index] = view.getUint32(offset + index * 4)
    }

    for (let index = 16; index < 64; index += 1) {
      const s0 = rotateRight(words[index - 15], 7) ^ rotateRight(words[index - 15], 18) ^ (words[index - 15] >>> 3)
      const s1 = rotateRight(words[index - 2], 17) ^ rotateRight(words[index - 2], 19) ^ (words[index - 2] >>> 10)
      words[index] = (words[index - 16] + s0 + words[index - 7] + s1) >>> 0
    }

    let a = h0
    let b = h1
    let c = h2
    let d = h3
    let e = h4
    let f = h5
    let g = h6
    let h = h7

    for (let index = 0; index < 64; index += 1) {
      const s1 = rotateRight(e, 6) ^ rotateRight(e, 11) ^ rotateRight(e, 25)
      const ch = (e & f) ^ (~e & g)
      const temp1 = (h + s1 + ch + SHA256_K[index] + words[index]) >>> 0
      const s0 = rotateRight(a, 2) ^ rotateRight(a, 13) ^ rotateRight(a, 22)
      const maj = (a & b) ^ (a & c) ^ (b & c)
      const temp2 = (s0 + maj) >>> 0

      h = g
      g = f
      f = e
      e = (d + temp1) >>> 0
      d = c
      c = b
      b = a
      a = (temp1 + temp2) >>> 0
    }

    h0 = (h0 + a) >>> 0
    h1 = (h1 + b) >>> 0
    h2 = (h2 + c) >>> 0
    h3 = (h3 + d) >>> 0
    h4 = (h4 + e) >>> 0
    h5 = (h5 + f) >>> 0
    h6 = (h6 + g) >>> 0
    h7 = (h7 + h) >>> 0
  }

  return [h0, h1, h2, h3, h4, h5, h6, h7]
    .map(word => word.toString(16).padStart(8, "0"))
    .join("")
}

function rotateRight(value, bits) {
  return (value >>> bits) | (value << (32 - bits))
}

const SHA256_K = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
]

function contributorId() {
  const key = "imaedge:contributor-animal-id"
  const current = localStorage.getItem(key)
  if (current) return current

  const adjectives = ["quiet", "golden", "clear", "bright", "steady", "brave", "silver", "warm", "wild", "fresh"]
  const nouns = ["otter", "fox", "lynx", "panda", "badger", "falcon", "heron", "seal", "turtle", "wombat"]
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

function recordId() {
  if (globalThis.crypto && typeof globalThis.crypto.randomUUID === "function") {
    return globalThis.crypto.randomUUID()
  }

  const random = new Uint8Array(16)

  if (globalThis.crypto && typeof globalThis.crypto.getRandomValues === "function") {
    globalThis.crypto.getRandomValues(random)
  } else {
    for (let index = 0; index < random.length; index += 1) {
      random[index] = Math.floor(Math.random() * 256)
    }
  }

  return [...random].map(byte => byte.toString(16).padStart(2, "0")).join("")
}

export const UploadQueue = {
  async mounted() {
    this.collectionId = this.el.dataset.collectionId
    this.csrf = document.querySelector("meta[name='csrf-token']").content
    this.input = this.el.querySelector("#image-picker")
    this.dropzone = this.input.closest("label")
    this.queueEl = this.el.querySelector("#client-queue")
    this.storageEl = document.querySelector("#storage-estimate")
    this.concurrencyEl = this.el.querySelector("#upload-concurrency")
    this.logEl = document.querySelector("#debug-log-output")
    this.copyLogButton = document.querySelector("#copy-debug-log")
    this.clearLogButton = document.querySelector("#clear-debug-log")
    this.records = []
    this.active = 0
    this.poll = null
    this.renderScheduled = false
    this.dragDepth = 0
    this.abortControllers = new Map()
    this.cancelledIds = new Set()

    this.input.addEventListener("click", () => this.log("image picker tapped"))
    this.input.addEventListener("change", event => {
      const files = [...event.target.files]
      this.log(`image picker selected ${files.length} file(s)`)
      this.addFiles(files)
    })
    this.queueEl.addEventListener("click", event => {
      const button = event.target.closest("[data-cancel-upload]")
      if (button) this.cancelUpload(button.dataset.cancelUpload)
      const retryButton = event.target.closest("[data-retry-upload]")
      if (retryButton) this.retryUpload(retryButton.dataset.retryUpload)
    })
    this.dropzone.addEventListener("dragenter", event => {
      event.preventDefault()
      this.dragDepth += 1
      this.setDropzoneActive(true)
    })
    this.dropzone.addEventListener("dragover", event => {
      event.preventDefault()
      event.dataTransfer.dropEffect = "copy"
    })
    this.dropzone.addEventListener("dragleave", () => {
      this.dragDepth = Math.max(0, this.dragDepth - 1)
      if (this.dragDepth === 0) this.setDropzoneActive(false)
    })
    this.dropzone.addEventListener("drop", event => {
      event.preventDefault()
      this.dragDepth = 0
      this.setDropzoneActive(false)
      const files = [...event.dataTransfer.files]
      this.log(`dropzone received ${files.length} file(s)`)
      this.addFiles(files)
    })
    this.concurrencyEl.addEventListener("change", () => this.pump())
    this.copyLogButton.addEventListener("click", () => navigator.clipboard.writeText(this.logEl.textContent))
    this.clearLogButton.addEventListener("click", () => this.setLog(""))

    this.records = (await allRecords(this.collectionId)).map(record => ({
      ...record,
      status: ["uploading", "preparing", "finalizing", "local storage"].includes(record.status) ? "queued" : record.status
    }))
    this.render()
    this.updateStorageEstimate()
    this.log(`queue loaded with ${this.records.length} local record(s)`)
    this.pump()

    this.poll = window.setInterval(() => this.refreshServerStates(), 15000)
  },

  destroyed() {
    if (this.poll) window.clearInterval(this.poll)
    this.abortControllers.forEach(controller => controller.abort())
  },

  setDropzoneActive(active) {
    this.dropzone.classList.toggle("border-ink", active)
    this.dropzone.classList.toggle("bg-brand-accent/[0.08]", active)
  },

  async addFiles(files) {
    for (const file of files) {
      if (!["image/jpeg", "image/png", "image/webp"].includes(file.type)) {
        this.log(`rejected unsupported file ${file.name} (${file.type || "unknown"})`)
        continue
      }

      const id = recordId()
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
        if (this.cancelledIds.has(id)) continue

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
      const record = this.records.find(item => item.status === "queued")
      if (!record) return

      this.active += 1
      this.upload(record).finally(() => {
        this.active -= 1
        this.pump()
      })
    }
  },

  async upload(record) {
    const controller = new AbortController()
    this.abortControllers.set(record.id, controller)

    try {
      record.status = "preparing"
      this.render()

      if (!record.sessionId) {
        const session = await this.createSession(record, controller.signal)
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

      const status = await this.fetchStatus(record, controller.signal)
      if (status.duplicate) {
        record.status = "already present"
        record.progress = 100
        await deleteRecord(record.id)
        this.log(`server duplicate ${record.name}, local copy released`)
        this.removeSoon(record)
        this.updateStorageEstimate()
        return
      }

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
      this.render()
      await this.uploadMissingChunks(record, status.missing_chunks, controller.signal)

      record.status = "finalizing"
      this.render()
      const finalized = await this.finalize(record, controller.signal)
      if (finalized.duplicate) {
        record.status = "already present"
        record.progress = 100
        await deleteRecord(record.id)
        this.log(`server duplicate ${record.name}, local copy released`)
        this.removeSoon(record)
        this.updateStorageEstimate()
        return
      }

      record.status = "processing"
      record.progress = 100
      await deleteRecord(record.id)
      this.log(`finalized ${record.name}, local copy released`)
      this.removeSoon(record)
      this.updateStorageEstimate()
    } catch (error) {
      if (this.cancelledIds.has(record.id) || error?.name === "AbortError") {
        this.log(`upload cancelled ${record.name}`)
        return
      }

      record.status = "failed upload"
      record.error = String(error)
      await putRecord(record).catch(() => {})
      this.log(`upload failed ${record.name}: ${record.error}`)
      this.render()
    } finally {
      this.abortControllers.delete(record.id)
    }
  },

  async createSession(record, signal) {
    const response = await this.jsonFetch(`/i/${this.collectionId}/uploads`, {
      method: "POST",
      signal,
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

  async fetchStatus(record, signal) {
    return this.jsonFetch(`/i/${this.collectionId}/uploads/${record.sessionId}`, {signal})
  },

  async uploadMissingChunks(record, missingChunks, signal) {
    const started = performance.now()
    const initialDone = record.totalChunks - missingChunks.length
    let uploaded = initialDone * record.chunkSize
    let doneCount = initialDone
    let queue = [...missingChunks]

    while (queue.length) {
      const index = queue.shift()
      const start = index * record.chunkSize
      const end = Math.min(start + record.chunkSize, record.size)
      const chunk = record.file.slice(start, end)

      await this.putChunkWithRetry(record, index, chunk, signal)

      uploaded += chunk.size
      doneCount += 1
      record.progress = Math.min(99, Math.round((uploaded / record.size) * 100))
      record.chunksDone = doneCount
      record.chunksTotal = record.totalChunks
      const seconds = Math.max((performance.now() - started) / 1000, 0.1)
      record.speed = `${formatBytes(uploaded / seconds)}/s`
      this.scheduleRender()
    }

    // Resync: if the server still reports missing chunks (e.g. a stall
    // dropped a write), upload those before finalize.
    const status = await this.fetchStatus(record, signal)
    if (status.missing_chunks && status.missing_chunks.length) {
      this.log(`re-uploading ${status.missing_chunks.length} chunk(s) reported missing by server`)
      await this.uploadMissingChunks(record, status.missing_chunks, signal)
    }
  },

  async putChunkWithRetry(record, index, chunk, signal) {
    // A stalled file must release its queue slot. The local copy remains in
    // IndexedDB and can be resumed explicitly with the retry button.
    const maxAttempts = 1
    let attempt = 0
    let lastError

    while (attempt < maxAttempts) {
      attempt += 1
      const controller = new AbortController()
      const abortAttempt = () => controller.abort()
      signal.addEventListener("abort", abortAttempt, {once: true})
      let timedOut = false
      const timer = setTimeout(() => {
        timedOut = true
        controller.abort()
      }, CHUNK_REQUEST_TIMEOUT_MS)

      try {
        const response = await fetch(
          `/i/${this.collectionId}/uploads/${record.sessionId}/chunks/${index}`,
          {
            method: "PUT",
            headers: {"x-csrf-token": this.csrf, "content-type": "application/octet-stream"},
            body: chunk,
            signal: controller.signal,
          },
        )

        if (response.ok) return

        const detail = await response.text().catch(() => "")
        lastError = new Error(`chunk ${index} HTTP ${response.status}: ${detail}`)
      } catch (error) {
        if (timedOut && !signal.aborted) {
          lastError = new Error(`chunk ${index} timed out after ${Math.round(CHUNK_REQUEST_TIMEOUT_MS / 1000)}s`)
          lastError.name = "TimeoutError"
        } else {
          lastError = error
        }
      } finally {
        clearTimeout(timer)
        signal.removeEventListener("abort", abortAttempt)
      }

      if (signal.aborted) throw new DOMException("Upload cancelled", "AbortError")

      if (attempt < maxAttempts) {
        const backoff = Math.min(2_000 * attempt, 8_000)
        this.log(`chunk ${index} attempt ${attempt} failed (${String(lastError)}), retrying in ${backoff}ms`)
        await waitWithSignal(backoff, signal)
      }
    }

    throw lastError
  },

  async finalize(record, signal) {
    return this.jsonFetch(`/i/${this.collectionId}/uploads/${record.sessionId}/finalize`, {
      method: "POST",
      signal,
      timeoutMs: FINALIZE_REQUEST_TIMEOUT_MS,
    })
  },

  async cancelUpload(recordId) {
    const record = this.records.find(item => item.id === recordId)
    if (!record) return

    this.cancelledIds.add(record.id)
    this.abortControllers.get(record.id)?.abort()
    this.records = this.records.filter(item => item.id !== record.id)
    this.render()

    await deleteRecord(record.id).catch(() => {})
    this.updateStorageEstimate()
    this.log(`removed ${record.name} from local upload queue`)

    if (record.sessionId) {
      try {
        await this.jsonFetch(`/i/${this.collectionId}/uploads/${record.sessionId}`, {method: "DELETE"})
        this.log(`cancelled server upload ${record.name}`)
      } catch (error) {
        this.log(`server could not cancel ${record.name}: ${String(error)}`)
      }
    }
  },

  async retryUpload(recordId) {
    const record = this.records.find(item => item.id === recordId)
    if (!record || record.status !== "failed upload") return

    record.status = "queued"
    record.error = ""
    await putRecord(record).catch(() => {})
    this.render()
    this.pump()
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
    const {
      timeoutMs = CONTROL_REQUEST_TIMEOUT_MS,
      signal: parentSignal,
      headers = {},
      ...fetchOptions
    } = options
    const controller = new AbortController()
    let timedOut = false
    const abortFromParent = () => controller.abort()

    if (parentSignal?.aborted) throw new DOMException("Upload cancelled", "AbortError")
    parentSignal?.addEventListener("abort", abortFromParent, {once: true})

    const timer = window.setTimeout(() => {
      timedOut = true
      controller.abort()
    }, timeoutMs)

    try {
      const response = await fetch(url, {
        ...fetchOptions,
        signal: controller.signal,
        headers: {
          "accept": "application/json",
          "content-type": "application/json",
          "x-csrf-token": this.csrf,
          ...headers,
        }
      })

      const text = await response.text()
      const body = text ? parseJsonOrText(text) : {}
      if (!response.ok) throw new Error(`HTTP ${response.status}: ${typeof body === "string" ? body : JSON.stringify(body)}`)
      return body
    } catch (error) {
      if (timedOut && !parentSignal?.aborted) {
        const timeoutError = new Error(`request timed out after ${Math.round(timeoutMs / 1000)}s`)
        timeoutError.name = "TimeoutError"
        throw timeoutError
      }
      throw error
    } finally {
      window.clearTimeout(timer)
      parentSignal?.removeEventListener("abort", abortFromParent)
    }
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
    this.storageEl.innerHTML = `<b class="text-ink font-semibold">${formatBytes(estimate.usage)}</b> / ~${formatBytes(available)} free`
    const bar = document.querySelector("#storage-bar")
    if (bar && estimate.quota) {
      const pct = Math.min(100, (estimate.usage / estimate.quota) * 100)
      bar.style.width = `${pct.toFixed(2)}%`
    }
  },

  scheduleRender() {
    if (this.renderScheduled) return
    this.renderScheduled = true
    window.requestAnimationFrame(() => {
      this.renderScheduled = false
      this.render()
    })
  },

  render() {
    const waitingEl = document.querySelector("#queue-waiting")
    if (waitingEl) {
      const waiting = this.records.filter(r => !["already present", "complete"].includes(r.status)).length
      waitingEl.textContent = `${waiting} waiting`
    }

    if (!this.records.length) {
      this.queueEl.innerHTML = ""
      return
    }

    this.queueEl.innerHTML = this.records.map(record => {
      const progress = record.progress || 0
      const isActive = ["uploading", "preparing", "finalizing"].includes(record.status)
      const chunks =
        record.chunksTotal && ["uploading", "finalizing"].includes(record.status)
          ? ` · ${record.chunksDone}/${record.chunksTotal}`
          : ""
      const speed = record.status === "uploading" && record.speed ? ` · ${escapeHtml(record.speed)}` : ""
      const pct = isActive ? ` · ${progress}%` : ""
      const canCancel = !["already present", "processing", "complete"].includes(record.status)

      return `
        <article class="bg-white border border-black/[0.06] rounded-[3px] py-2.5 px-3 flex flex-col gap-2 font-brand-sans text-[13.5px]">
          <div class="flex items-center justify-between gap-3">
            <strong class="font-medium text-ink truncate min-w-0">${escapeHtml(record.name)}</strong>
            <div class="flex shrink-0 items-center gap-2">
              <span class="font-brand-mono text-[11.5px] text-mid whitespace-nowrap">${escapeHtml(record.status)}${chunks}${speed}${pct}</span>
              ${record.status === "failed upload" ? `<button type="button" data-retry-upload="${escapeHtml(record.id)}" class="rounded-[3px] border border-ink px-2 py-1 text-[11.5px] text-ink hover:bg-ink hover:text-paper">retry</button>` : ""}
              ${canCancel ? `<button type="button" data-cancel-upload="${escapeHtml(record.id)}" class="rounded-[3px] border border-black/[0.16] px-2 py-1 text-[11.5px] text-mid hover:border-warn hover:text-warn">cancel</button>` : ""}
            </div>
          </div>
          <div class="h-1 bg-tint overflow-hidden ${isActive ? "queue-bar-active" : ""}">
            <div class="block h-full bg-ink transition-[width] duration-200" style="width:${progress}%"></div>
          </div>
          ${record.error ? `<code class="font-brand-mono text-[11.5px] text-warn break-all">${escapeHtml(record.error)}</code>` : ""}
        </article>
      `
    }).join("")
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

function waitWithSignal(milliseconds, signal) {
  return new Promise((resolve, reject) => {
    if (signal.aborted) {
      reject(new DOMException("Upload cancelled", "AbortError"))
      return
    }

    const timer = window.setTimeout(() => {
      signal.removeEventListener("abort", abort)
      resolve()
    }, milliseconds)
    const abort = () => {
      window.clearTimeout(timer)
      reject(new DOMException("Upload cancelled", "AbortError"))
    }
    signal.addEventListener("abort", abort, {once: true})
  })
}
