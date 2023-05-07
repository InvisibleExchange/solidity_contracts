const {
  sendSpotOrder,
  sendDeposit,
  sendWithdrawal,
  sendPerpOrder,
  sendSplitOrder,
} = require("../../../invisible_react/src/app_logic/transactions/constructOrders");
const User = require("../../../invisible_react/src/app_logic/users/Invisibl3User");

async function test() {
  let user = User.fromPrivKey(1010101010);

  await user.login();

  for (let i = 0; i < 1; i++) {
    await sendDeposit(user, 123, 2000, 55555);
    await sendDeposit(user, 123, 2, 54321);
  }

  for (let i = 0; i < 1; i++) {
    await sendSpotOrder(user, "Buy", 10, 54321, 55555, 1, 1000, 0.1);
    await sendSpotOrder(user, "Sell", 10, 54321, 55555, 1, 1000, 0.1);
  }

  console.log("Done");
}

test();
