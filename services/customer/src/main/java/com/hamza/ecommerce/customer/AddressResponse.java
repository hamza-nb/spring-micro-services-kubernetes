package com.hamza.ecommerce.customer;

public record AddressResponse(
        String street,
        String houseNumber,
        String zipCode
) {
}
