const functions = require("firebase-functions")
const fcl = require("@onflow/fcl")
const t = require("@onflow/types")

const contractAddress = functions.config().flow.contract_address
const endpoint = functions.config().flow.flow_endpoint

const script = `
  pub fun main(addr: Address, id: UInt64): AnyStruct {
    let path = StoragePath(identifier: "Avataaars_".concat(id.toString()))!
    let content = getAuthAccount(addr)
      .borrow<&String>(from: path)!
    return content
}`


exports.avataaar = functions.https.onRequest(async (request, response) => {
  const id = request.query.id
  console.log({id, contractAddress})

  fcl.config({
    "accessNode.api": endpoint,
  })

  const args = [
    fcl.arg(contractAddress, t.Address),
    fcl.arg(Number(id), t.UInt64),
  ]
  const res = await fcl.send([fcl.script`${script}`, fcl.args(args)])
  const decoded = await fcl.decode(res)
  console.log(decoded)

  response.setHeader("Content-Type", "image/svg+xml")
  response.send(decoded)
})
