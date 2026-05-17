import { BigInt } from "@graphprotocol/graph-ts"
import { Transfer as TransferEvent } from "../generated/RWAToken/RWAToken"
import { Account, Transfer } from "../generated/schema"

export function handleTransfer(event: TransferEvent): void {
  let fromAddress = event.params.from.toHex()
  let toAddress = event.params.to.toHex()

  // Загружаем или создаем аккаунт отправителя
  let fromAccount = Account.load(fromAddress)
  if (fromAccount == null) {
    fromAccount = new Account(fromAddress)
    fromAccount.hasKYC = false
    fromAccount.tokenBalance = BigInt.fromI32(0)
  }
  fromAccount.tokenBalance = fromAccount.tokenBalance.minus(event.params.value)
  fromAccount.save()

  // Загружаем или создаем аккаунт получателя
  let toAccount = Account.load(toAddress)
  if (toAccount == null) {
    toAccount = new Account(toAddress)
    toAccount.hasKYC = false
    toAccount.tokenBalance = BigInt.fromI32(0)
  }
  toAccount.tokenBalance = toAccount.tokenBalance.plus(event.params.value)
  toAccount.save()

  // Сохраняем саму сущность трансфера для истории
  let transfer = new Transfer(
    event.transaction.hash.toHex() + "-" + event.logIndex.toString()
  )
  transfer.from = fromAddress
  transfer.to = toAddress
  transfer.amount = event.params.value
  transfer.blockNumber = event.block.number
  transfer.blockTimestamp = event.block.timestamp
  transfer.transactionHash = event.transaction.hash
  transfer.save()
}