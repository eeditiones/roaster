// Sends a payload to the server without going through Fore, like a tampered or hand-made client.
const tamper = document.getElementById('tamper')
const payload = tamper.querySelector('textarea')
const result = tamper.querySelector('output')
const route = new URL('../api/fore/demo', location.href).href

tamper.querySelector('.curl').textContent =
    `curl -X POST -H 'Content-Type: application/xml' --data '<order>…</order>' ${route}`

tamper.querySelector('button').addEventListener('click', async () => {
    result.textContent = 'Sending …'
    try {
        const response = await fetch(route, {
            method: 'POST',
            headers: { 'Content-Type': 'application/xml' },
            body: payload.value
        })
        const body = await response.json().catch(() => ({}))
        result.textContent = `${response.status} ${response.statusText}\n` + JSON.stringify(body.value ?? body, null, 2)
        result.dataset.status = response.ok ? 'ok' : 'rejected'
    } catch (error) {
        result.textContent = String(error)
        result.dataset.status = 'rejected'
    }
})

// When Fore stops a submission (status 0) show the browser's own popup on the first invalid field,
// with the alert of its bind as message. The text is written once, in the fx-bind.
document.addEventListener(
    'submit-error',
    (event) => {
        if (event.detail?.status !== 0) return

        const control = document.querySelector('fx-control[invalid]')
        const input = control?.querySelector('input')
        if (!input) return

        input.setCustomValidity(control.modelItem?.alerts?.[0] ?? 'This value is not valid')
        input.reportValidity()
        input.addEventListener('input', () => input.setCustomValidity(''), { once: true })
        // Fore does not let this event bubble, so listen while it travels down to the submission
    },
    true
)

// Shows the binds of this page, the same elements the server compiles. They are read from the page,
// so what is displayed can not differ from what is validated.
function describeBinds(binds, depth = 0) {
    const indent = '    '.repeat(depth)
    return [...binds]
        .map((bind) => {
            const attributes = [...bind.attributes].map(({ name, value }) => `${name}="${value}"`)
            const open = `${indent}<fx-bind ${attributes.join(`\n${indent}         `)}`
            const children = bind.querySelectorAll(':scope > fx-bind')
            return children.length
                ? `${open}>\n${describeBinds(children, depth + 1)}\n${indent}</fx-bind>`
                : `${open}></fx-bind>`
        })
        .join('\n')
}

const listing = document.querySelector('#binds code')
const binds = document.querySelectorAll('fx-model > fx-bind')
if (listing && binds.length) listing.textContent = describeBinds(binds)
