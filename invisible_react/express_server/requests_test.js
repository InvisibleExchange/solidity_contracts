const axios = require("axios");

for (let i = 0; i < 10; i++) {
  axios.post(`http://localhost:4000/execute_deposit`, {}).then((res) => {
    console.log(res);
  });
}

// for (let i = 0; i < 10; i++) {
//   axios.post(`http://localhost:4000/execute_deposit`, {}).then((res) => {
//     console.log(res);
//   });
// }
