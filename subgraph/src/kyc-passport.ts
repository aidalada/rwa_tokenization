import { BigInt } from "@graphprotocol/graph-ts"
import { Transfer as KYCEvent } from "../generated/KYCPassport/KYCPassport"
import { Account, KycUpdate } from "../generated/schema"

export function handleKYCTransfer(event: KYCEvent): void {
  let zeroAddress = "0x0000000000000000000000000000000000000000"
  let userAddress = event.params.to.toHex()
  let isMint = true

  if (userAddress == zeroAddress) {
    userAddress = event.params.from.toHex()
    isMint = false
  }

  let account = Account.load(userAddress)
  if (account == null) {
    account = new Account(userAddress)
    account.tokenBalance = BigInt.fromI32(0)
  }
  account.hasKYC = isMint
  account.save()

  let update = new KycUpdate(event.transaction.hash.toHex() + "-" + event.logIndex.toString())
  update.account = isMint ? event.params.to : event.params.from
  update.status = isMint
  update.blockTimestamp = event.block.timestamp
  update.save()
}