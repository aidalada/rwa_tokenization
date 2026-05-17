import { BigInt } from "@graphprotocol/graph-ts"
import { Transfer as TransferEvent, Approval as ApprovalEvent } from "../generated/RWAToken/RWAToken"
import { Account, Transfer, Approval } from "../generated/schema"

export function handleTransfer(event: TransferEvent): void {
  let fromAddress = event.params.from.toHex()
  let toAddress = event.params.to.toHex()

  let fromAccount = Account.load(fromAddress)
  if (fromAccount == null) {
    fromAccount = new Account(fromAddress)
    fromAccount.hasKYC = false
    fromAccount.tokenBalance = BigInt.fromI32(0)
  }
  fromAccount.tokenBalance = fromAccount.tokenBalance.minus(event.params.value)
  fromAccount.save()

  let toAccount = Account.load(toAddress)
  if (toAccount == null) {
    toAccount = new Account(toAddress)
    toAccount.hasKYC = false
    toAccount.tokenBalance = BigInt.fromI32(0)
  }
  toAccount.tokenBalance = toAccount.tokenBalance.plus(event.params.value)
  toAccount.save()

  let transfer = new Transfer(event.transaction.hash.toHex() + "-" + event.logIndex.toString())
  transfer.from = event.params.from
  transfer.to = event.params.to
  transfer.value = event.params.value
  transfer.transactionHash = event.transaction.hash
  transfer.save()
}

export function handleApproval(event: ApprovalEvent): void {
  let approval = new Approval(event.transaction.hash.toHex() + "-" + event.logIndex.toString())
  approval.owner = event.params.owner
  approval.spender = event.params.spender
  approval.value = event.params.value
  approval.transactionHash = event.transaction.hash
  approval.save()
}