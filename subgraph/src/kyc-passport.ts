import { BigInt } from "@graphprotocol/graph-ts"
import { Transfer as KYCEvent } from "../generated/KYCPassport/KYCPassport"
import { Account } from "../generated/schema"

export function handleKYCTransfer(event: KYCEvent): void {
  let zeroAddress = "0x0000000000000000000000000000000000000000"
  let userAddress = event.params.to.toHex()

  // Если токен идет не от нулевого адреса, значит это сжигание (возврат в ноль)
  if (userAddress == zeroAddress) {
    userAddress = event.params.from.toHex()
    let account = Account.load(userAddress)
    if (account != null) {
      account.hasKYC = false
      account.save()
    }
    return
  }

  // В противном случае — это минт нового KYC паспорта пользователю
  let account = Account.load(userAddress)
  if (account == null) {
    account = new Account(userAddress)
    account.tokenBalance = BigInt.fromI32(0)
  }
  account.hasKYC = true
  account.save()
}