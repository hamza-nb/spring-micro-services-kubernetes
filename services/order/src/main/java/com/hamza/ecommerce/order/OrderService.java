package com.hamza.ecommerce.order;

import com.hamza.ecommerce.kafka.OrderConfirmation;
import com.hamza.ecommerce.customer.CustomerClient;
import com.hamza.ecommerce.exception.BusinessException;
import com.hamza.ecommerce.kafka.OrderProducer;
import com.hamza.ecommerce.orderline.OrderLineRequest;
import com.hamza.ecommerce.orderline.OrderLineService;
import com.hamza.ecommerce.payment.PaymentClient;
import com.hamza.ecommerce.payment.PaymentRequest;
import com.hamza.ecommerce.product.ProductClient;
import com.hamza.ecommerce.product.PurchaseRequest;
import jakarta.persistence.EntityNotFoundException;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class OrderService {

    private final OrderRepository repository;
    private final OrderMapper mapper;
    private final CustomerClient customerClient;
    private final PaymentClient paymentClient;
    private final ProductClient productClient;
    private final OrderLineService orderLineService;
    private final OrderProducer orderProducer;

    @Transactional
    public Integer createOrder(OrderRequest request) {
        var customer = this.customerClient.findCustomerById(request.customerId())
                .orElseThrow(() -> new BusinessException("Cannot create order:: No customer exists with the provided ID"));

        var purchasedProducts = productClient.purchaseProducts(request.products());

        System.err.println("=======---111111---==========");
        System.err.println(purchasedProducts);
        System.err.println("=======---22222222---==========");
        System.err.println(mapper.toOrder(request));
        System.err.println("=======---3333333---==========");
        var order = this.repository.save(mapper.toOrder(request));
        System.err.println(order);
        System.err.println("=======------==========");
        for (PurchaseRequest purchaseRequest : request.products()) {
            orderLineService.saveOrderLine(
                    new OrderLineRequest(
                            null,
                            order.getId(),
                            purchaseRequest.productId(),
                            purchaseRequest.quantity()
                    )
            );
        }
        var paymentRequest = new PaymentRequest(
                request.amount(),
                request.paymentMethod(),
                order.getId(),
                order.getReference(),
                customer
        );
        paymentClient.requestOrderPayment(paymentRequest);

        orderProducer.sendOrderConfirmation(
                new OrderConfirmation(
                        request.reference(),
                        request.amount(),
                        request.paymentMethod(),
                        customer,
                        purchasedProducts
                )
        );

        return order.getId();
    }

    public List<OrderResponse> findAllOrders() {
        return this.repository.findAll()
                .stream()
                .map(this.mapper::fromOrder)
                .collect(Collectors.toList());
    }

    public OrderResponse findById(Integer id) {
        return this.repository.findById(id)
                .map(this.mapper::fromOrder)
                .orElseThrow(() -> new EntityNotFoundException(String.format("No order found with the provided ID: %d", id)));
    }
}
